// Offline only: render the four original campaign/menu voices to looped PCM.
#include "engine/synth.hpp"
#include "engine/paula.hpp"
#include <cstdio>
#include <fstream>
#include <iterator>
#include <map>
#include <string>
#include <vector>
ms::Synth synth{};ms::paula::Paula device{};
void w16(void*,uint16_t r,uint16_t v){ms::paula::write16(device,r,v);}
void w32(void*,uint16_t r,uint32_t v){ms::paula::write32(device,r,v);}
uint16_t r16(void*,uint16_t r){return ms::paula::read16(device,r);}
const ms::SynthHw hw{nullptr,w16,w32,r16};
void irq(void*){ms::synthInt4(synth,hw);}
void le(FILE*f,uint32_t v,unsigned n){while(n--){fputc(v&255,f);v>>=8;}}
std::string state(){
 std::string s;auto add=[&](uint32_t v){for(int i=0;i<4;++i){s+=char(v&255);v>>=8;}};
 add(synth.uwTempo);
 for(auto&v:synth.aVoice){
  add(v.ulSeqPos);add(v.uwNoteLeft);add(v.uwNoteLen);add(v.uwNote);add(v.ubSp);add(v.wTranspose);
  add(v.ulPitchRef);add(v.ulEnvRef);add(v.uwBaseVol);add(v.uwBasePer);add(v.uwEnvPhase);add(v.ubEnvTimer);
  for(auto n:v.aubStack)s+=char(n);
 }
 return s;
}
int main(int argc,char**argv){
#ifdef MOONSTONE_EXTERNAL_SYNTH
 extern bool moonstoneLoadSynthTables();if(!moonstoneLoadSynthTables())return 6;
#endif
 if(argc!=3)return 2;std::ifstream f(argv[1],std::ios::binary);std::vector<uint8_t>mem((std::istreambuf_iterator<char>(f)),{});if(mem.size()!=0x90000)return 3;
 ms::paula::reset(device,{48000,100,0},{mem.data(),0,(uint32_t)mem.size()});ms::synthInit(synth,hw,0x1000);
 const uint32_t banks[5]={0x10000,0x20000,0x40000,0x60000,0x80000};ms::synthRelocate(synth,banks);
 for(int i=0;i<4;++i)ms::synthStart(synth,hw,110+i,i);
 std::map<std::string,unsigned>seen;std::vector<int16_t>pcm;int16_t frame[1920];unsigned begin=0,end=0;
 for(unsigned tick=0;tick<15000;++tick){
  auto key=state();auto it=seen.find(key);
  if(it!=seen.end() && tick-it->second>50){begin=it->second;end=tick;break;}
  seen[key]=tick;ms::synthTick(synth,hw);ms::paula::render(device,frame,960,{nullptr,nullptr,irq});pcm.insert(pcm.end(),frame,frame+1920);
 }
 if(!end)return 4;FILE*out=fopen(argv[2],"wb");if(!out)return 5;
 fwrite("RIFF",1,4,out);le(out,36+pcm.size()*2,4);fwrite("WAVEfmt ",1,8,out);le(out,16,4);le(out,1,2);le(out,2,2);le(out,48000,4);le(out,192000,4);le(out,4,2);le(out,16,2);fwrite("data",1,4,out);le(out,pcm.size()*2,4);for(auto n:pcm)le(out,(uint16_t)n,2);fclose(out);
 printf("{\"loop_begin\":%u,\"loop_end\":%u,\"ticks\":%u,\"sequences\":[110,111,112,113]}\n",begin*960,end*960,end);
}
