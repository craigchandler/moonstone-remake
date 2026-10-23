from pathlib import Path
import ctypes
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import import_accel as accel
import import_ipf as ipf


class NativeImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which('c++'):raise unittest.SkipTest('Native kernel tests require a host compiler')
        cls.temporary=tempfile.TemporaryDirectory()
        cls.folder=Path(cls.temporary.name)
        subprocess.run(['c++','-std=c++17','-O2','-shared','-fPIC',
                        str(Path(__file__).resolve().parents[1]/'import_accel.cpp'),
                        '-o',str(cls.folder/'import-accel.so')],check=True)
        cls.previous=(accel._library,accel._loaded)
        accel._library=None;accel._loaded=False
        with patch.dict(os.environ,MOONSTONE_IMPORT_BIN=str(cls.folder)):cls.lib=accel.library()

    @classmethod
    def tearDownClass(cls):
        accel._library,accel._loaded=cls.previous
        cls.temporary.cleanup()

    def test_lzss_literals_overlap_and_invalid_references(self):
        for size in (0,1,7,8,9,1000):
            data=random.Random(size).randbytes(size)
            packed=b''.join(b'\0'+data[i:i+8] for i in range(0,size,8))
            self.assertEqual(accel.lzss_decode(packed),data)
        self.assertEqual(accel.lzss_decode(bytes([0x40,65,0,1])),b'A'*35)
        for data in (b'\x80\0',b'\x80\0\0',b'\x80\0\1'):
            with self.assertRaises(ValueError):accel.lzss_decode(data)

    def encoded(self,data):
        words=struct.unpack('>'+str(len(data)//4)+'I',data)
        return b''.join(struct.pack('>I',(w>>shift)&0x55555555) for shift in (1,0) for w in words)

    def sector(self,index,payload):
        info=bytes([255,4,index,11-index]);label=bytes(16)
        return b'\x44\x89\x44\x89'+self.encoded(info)+self.encoded(label)+self.encoded(struct.pack('>I',ipf.sector_checksum(info+label)))+self.encoded(struct.pack('>I',ipf.sector_checksum(payload)))+self.encoded(payload)

    def test_track_checks_all_alignments_wrap_and_corruption(self):
        payloads=[random.Random(n).randbytes(512) for n in range(11)]
        raw=b''.join(self.sector(n,p)+b'\x55'*16 for n,p in enumerate(payloads))
        bits=''.join(f'{b:08b}' for b in raw)
        for shift in range(8):
            at=503*8+shift
            rotated=int(bits[at:]+bits[:at],2).to_bytes(len(raw),'big')
            self.assertEqual(accel.track_sectors(rotated,4),payloads)
            with patch.object(accel,'library',return_value=None):
                self.assertEqual(ipf.sectors_from_track(rotated,4),payloads)
        broken=bytearray(raw);broken[100]^=1
        with self.assertRaises(ValueError):accel.track_sectors(bytes(broken),4)
        conflicting=self.sector(0,bytes(512))+raw
        with self.assertRaises(ValueError):accel.track_sectors(conflicting,4)
        with self.assertRaises(ValueError) as error:accel.track_sectors(bytes(12000),1)
        self.assertFalse(error.exception.had_sync)

    def test_layer_checks_all_colours_missing_extra_overlap_and_bounds(self):
        import numpy as np
        from import_classic_layers import RGBA_WORDS
        source=np.zeros((8,9,4),dtype=np.uint8)
        source[2,3]=[1,2,3,255];source[4,5]=[11,22,33,255]
        indices=np.zeros((8,9),dtype=np.uint8);indices[2,3]=1
        page=np.array([[[255,255,255,255],[11,22,33,255]]],dtype=np.uint8)
        pieces=[{'page':0,'region':[0,0,1,1],'offset':[3,2],'slot':0},
                {'page':0,'region':[1,0,1,1],'offset':[5,4],'slot':-1}]
        args=(source,indices,[page],pieces,[0,0,9,8],RGBA_WORDS,5)
        self.assertEqual(accel.verify_pose(*args),5)
        for bad in (pieces[:1],pieces+pieces[:1],pieces+[dict(pieces[1],offset=[8,7])],
                    [dict(pieces[0],region=[0,0,3,1]),pieces[1]]):
            with self.assertRaises(ValueError):accel.verify_pose(source,indices,[page],bad,[0,0,9,8],RGBA_WORDS,5)
        changed=RGBA_WORDS.copy();changed[:,0]=RGBA_WORDS[0,0];changed[4,0]=RGBA_WORDS[1,0]
        fixed=source.copy();fixed[2,3]=RGBA_WORDS[0,0:1].view(np.uint8)
        with self.assertRaisesRegex(ValueError,'failed: 5'):
            accel.verify_pose(fixed,None,[page],pieces,[0,0,9,8],changed,5)


if __name__=='__main__':unittest.main()
