// OFFLINE importer only. The shipped Godot game plays the resulting PCM files.
// Links the pinned reference port's independently testable synth/Paula helpers;
// does not execute an Amiga executable or write to the original files.
#include "engine/synth.hpp"
#include "engine/paula.hpp"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

ms::Synth synth{};
ms::paula::Paula device{};
void write16(void*, uint16_t r, uint16_t v) { ms::paula::write16(device,r,v); }
void write32(void*, uint16_t r, uint32_t v) { ms::paula::write32(device,r,v); }
uint16_t read16(void*, uint16_t r) { return ms::paula::read16(device,r); }
const ms::SynthHw hw{nullptr,write16,write32,read16};
void interrupt(void*) { ms::synthInt4(synth,hw); }
void le(FILE* f, uint32_t v, unsigned bytes) { while(bytes--) { fputc(v&255,f); v>>=8; } }
int main(int argc, char** argv) {
    // memory, output, seconds, mono(1)/stereo(2), sequence(s on consecutive channels)
    if(argc<6) return 2;
    std::ifstream input(argv[1],std::ios::binary);
    std::vector<uint8_t> mem((std::istreambuf_iterator<char>(input)),{});
    if(mem.size()!=0x90000) return 3;
    constexpr unsigned rate=48000;
    ms::paula::reset(device,{rate,100,0},{mem.data(),0,(uint32_t)mem.size()});
    ms::synthInit(synth,hw,0x1000);
    const uint32_t banks[5]={0x10000,0x20000,0x40000,0x60000,0x80000};
    ms::synthRelocate(synth,banks);
    for(int i=5;i<argc;++i) ms::synthStart(synth,hw,(uint16_t)atoi(argv[i]),(uint16_t)(i-5));
    std::vector<int16_t> pcm;
    int16_t frame[960*2];
    const bool mono=atoi(argv[4])==1;
    for(int tick=0;tick<atoi(argv[3])*50;++tick) {
        ms::synthTick(synth,hw);
        ms::paula::render(device,frame,960,{nullptr,nullptr,interrupt});
        for(int j=0;j<960;++j) {
            // A single voice is on the left; centre it without changing gain.
            if(mono) pcm.push_back(frame[2*j]);
            else {pcm.push_back(frame[2*j]);pcm.push_back(frame[2*j+1]);}
        }
        bool running=false;
        for(auto& voice:synth.aVoice) running |= voice.ulSeqPos!=0;
        if(!running && tick>5) break;
    }
    // Trim only terminal silence, retaining 40 ms at the end. No normalisation.
    size_t last=pcm.size();
    while(last && pcm[last-1]==0) --last;
    if(last==0) return 4;
    pcm.resize(std::min(pcm.size(),last+rate*(mono?1:2)/25));
    FILE* out=fopen(argv[2],"wb"); if(!out) return 5;
    const unsigned channels=mono?1:2, bytes=pcm.size()*2;
    fwrite("RIFF",1,4,out);le(out,36+bytes,4);fwrite("WAVEfmt ",1,8,out);
    le(out,16,4);le(out,1,2);le(out,channels,2);le(out,rate,4);
    le(out,rate*channels*2,4);le(out,channels*2,2);le(out,16,2);
    fwrite("data",1,4,out);le(out,bytes,4);
    for(int16_t value:pcm) le(out,(uint16_t)value,2);
    fclose(out);
}
