// Offline importer: original sound tables are read from the user's extracted
// data, never compiled into a distributed helper. The ABI is explicit LE bytes.
#include "engine/synth_data.hpp"
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <vector>
#include <cstring>
namespace ms {
uint8_t kSynthBlob[kSynthBlobSize]{};
SynthInstrument kSynthInst[kSynthInstCount]{};
uint8_t kSynthWave[kSynthWaveSize]{};
const SynthTables kSynthTables{kSynthBlob,kSynthInst};
}
bool moonstoneLoadSynthTables() {
    const char* path=std::getenv("MOONSTONE_SYNTH_TABLES");
    if(!path)return false;
    std::ifstream input(path,std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)),{});
    if(bytes.size()!=8+ms::kSynthBlobSize+ms::kSynthWaveSize+14*ms::kSynthInstCount ||
       std::memcmp(bytes.data(),"MSST0001",8))return false;
    size_t at=8;
    std::memcpy(ms::kSynthBlob,bytes.data()+at,ms::kSynthBlobSize);at+=ms::kSynthBlobSize;
    std::memcpy(ms::kSynthWave,bytes.data()+at,ms::kSynthWaveSize);at+=ms::kSynthWaveSize;
    auto read=[&](unsigned n){uint32_t v=0;for(unsigned i=0;i<n;++i)v|=uint32_t(bytes[at++])<<(i*8);return v;};
    for(auto& row:ms::kSynthInst) {
        row.wLoop=int16_t(read(2));row.uwLoopOff=read(2);row.uwWords=read(2);
        auto bank=read(2);row.ulOffset=read(4);row.uwPitch=read(2);
        if(bank>=ms::kSynthBanks || row.ulOffset>0x90000 || row.uwPitch<ms::kSynthBlobBase ||
           row.uwPitch>=ms::kSynthBlobBase+ms::kSynthBlobSize)return false;
        row.ubBank=uint8_t(bank);
    }
    return true;
}
