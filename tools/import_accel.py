"""Optional native offline kernels; independent Python paths remain available."""
import ctypes as C
import os
from pathlib import Path

_library = None
_loaded = False


def library():
    global _library, _loaded
    if not _loaded:
        _loaded = True
        folder = os.environ.get('MOONSTONE_IMPORT_BIN')
        name = 'import-accel.dll' if os.name == 'nt' else 'import-accel.so'
        if folder and (Path(folder)/name).is_file():
            lib = C.CDLL(str(Path(folder)/name))
            pointer = C.c_void_p
            lib.ms_lzss.argtypes = [pointer,C.c_size_t,pointer,C.c_size_t]
            lib.ms_lzss.restype = C.c_int64
            lib.ms_track.argtypes = [pointer,C.c_size_t,C.c_int,pointer,C.POINTER(C.c_int)]
            lib.ms_track.restype = C.c_int
            lib.ms_verify_pose.argtypes = [pointer,*([C.c_int]*6),pointer,pointer,pointer,C.c_int,pointer,C.c_int,pointer,C.c_int]
            lib.ms_verify_pose.restype = C.c_int
            _library = lib
    return _library


def lzss_decode(source):
    # Maximum possible expansion is 34 bytes per two-byte reference, plus flags.
    output = C.create_string_buffer(max(1,len(source)*17))
    size = library().ms_lzss(source,len(source),output,len(output))
    if size < 0:raise ValueError('Invalid or truncated LZSS data')
    return output.raw[:size]


def track_sectors(raw, number):
    output = C.create_string_buffer(11*512)
    sync = C.c_int()
    count = library().ms_track(raw,len(raw),number,output,C.byref(sync))
    if count != 11:
        error = ValueError(f'track {number}: {count}/11 verified sectors')
        error.had_sync = bool(sync.value)
        raise error
    data = output.raw
    return [data[i*512:(i+1)*512] for i in range(11)]


def verify_pose(source, indices, pages, pieces, rect, colours, identities):
    import numpy as np
    source = np.ascontiguousarray(source)
    pages = [np.ascontiguousarray(page) for page in pages]
    indices = None if indices is None else np.ascontiguousarray(indices)
    colours = np.ascontiguousarray(colours)
    pointers = (C.c_void_p*len(pages))(*(page.ctypes.data for page in pages))
    sizes = (C.c_int*(len(pages)*2))(*(v for page in pages for v in (page.shape[1],page.shape[0])))
    records = (C.c_int*(len(pieces)*8))(*(v for p in pieces for v in (p['page'],*p['region'],*p['offset'],p['slot'])))
    code = library().ms_verify_pose(source.ctypes.data,source.shape[1],source.shape[0],*rect[:4],
                                   None if indices is None else indices.ctypes.data,pointers,sizes,len(pages),
                                   records,len(pieces),colours.ctypes.data,identities)
    if code:raise ValueError('Native layer verification failed: '+str(code))
    return identities
