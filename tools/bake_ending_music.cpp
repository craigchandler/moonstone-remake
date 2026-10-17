// Offline only: unpack the owned module and render the opening to ordinary PCM.
// No module player, hardware model, executable or disk data enters the game.
#include "engine/rnc.hpp"
#include "engine/modplay.hpp"
#include "engine/paula.hpp"
#include "rt/modsanitise.hpp"
#include <cstdio>
#include <fstream>
#include <iterator>
#include <vector>

ms::paula::Paula device{};
void w16(void*, uint16_t r, uint16_t v) { ms::paula::write16(device,r,v); }
void w32(void*, uint16_t r, uint32_t v) { ms::paula::write32(device,r,v); }
void le(FILE* f, uint32_t v, unsigned n) { while(n--) { fputc(v&255,f);v>>=8; } }
int main(int argc,char** argv) {
    if(argc!=4)return 2; // packed input, WAV, number of 50 Hz ticks
    std::ifstream in(argv[1],std::ios::binary);
    std::vector<uint8_t> packed((std::istreambuf_iterator<char>(in)),{});
    if(packed.size()!=60994)return 3;
    std::vector<uint8_t> mem(0x40000,0);
    const uint32_t bytes=ms::rncDecode(packed.data(),mem.data()+0x1000);
    if(bytes<1084 || bytes>0x30000)return 4;
    auto* mod=mem.data()+0x1000;
    // Retail victory6 module has the FLT4 tag, with the same31sample layout.
    if(mod[1080]!='F'||mod[1081]!='L'||mod[1082]!='T'||mod[1083]!='4')return 5;
    unsigned patterns=0;
    for(unsigned i=0;i<128;++i)if(mod[952+i]+1u>patterns)patterns=mod[952+i]+1u;
    if(1084+patterns*1024>bytes)return 6;
    rt::modSanitisePatterns(mod+1084,patterns);
    ms::ModPlayer player{};const ms::ModHw hw{nullptr,w16,w32};
    ms::paula::reset(device,{48000,100,0},{mem.data(),0,(uint32_t)mem.size()});
    if(!ms::modStart(player,mod,0x1000,0))return 7;
    const unsigned ticks=std::stoul(argv[3]);
    FILE* out=fopen(argv[2],"wb");if(!out)return 8;
    fwrite("RIFF",1,4,out);le(out,36+ticks*960*4,4);fwrite("WAVEfmt ",1,8,out);
    le(out,16,4);le(out,1,2);le(out,2,2);le(out,48000,4);le(out,192000,4);le(out,4,2);le(out,16,2);
    fwrite("data",1,4,out);le(out,ticks*960*4,4);
    int16_t pcm[960*2];
    for(unsigned tick=0;tick<ticks;++tick) {
        ms::modTick(player,hw);
        unsigned done=0;
        if(ms::modNeedsLoopPointers(player)) {
            done=40;ms::paula::render(device,pcm,done,{});
            ms::modLoopPointers(player,hw);
        }
        ms::paula::render(device,pcm+done*2,960-done,{});
        for(int16_t sample:pcm)le(out,(uint16_t)sample,2);
    }
    fclose(out);
    printf("Ending module: %u bytes, %u patterns, %u orders, %u ticks of stereo PCM\n",bytes,patterns,player.ubSongLen,ticks);
}
