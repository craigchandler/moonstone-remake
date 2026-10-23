// Optional offline decoding/verification kernels. No original game data.
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <vector>
#include <algorithm>

extern "C" {
// Returns decoded length, -1 for invalid input, -2 for insufficient capacity.
int64_t ms_lzss(const uint8_t* src, size_t size, uint8_t* out, size_t capacity) {
    size_t p=0, n=0;
    while (p<size) {
        unsigned flags=src[p++];
        for (int bit=0;bit<8 && p<size;++bit,flags<<=1) {
            if (!(flags&128)) {
                if(n==capacity)return -2;
                out[n++]=src[p++];
            } else {
                if(size-p<2)return -1;
                unsigned word=(src[p]<<8)|src[p+1];p+=2;
                unsigned distance=word&2047, count=34-(word>>11);
                if(!distance || distance>n)return -1;
                if(count>capacity-n)return -2;
                while(count--){out[n]=out[n-distance];++n;}
            }
        }
    }
    return int64_t(n);
}

static uint32_t be32(const uint8_t* p) {
    return (uint32_t(p[0])<<24)|(uint32_t(p[1])<<16)|(uint32_t(p[2])<<8)|p[3];
}
static void unpack(const uint8_t* p,uint8_t* out,size_t size) {
    for(size_t i=0;i<size;i+=4) {
        uint32_t value=((be32(p+i)&0x55555555)<<1)|(be32(p+size+i)&0x55555555);
        out[i]=value>>24;out[i+1]=value>>16;out[i+2]=value>>8;out[i+3]=value;
    }
}
static uint32_t checksum(const uint8_t* p,size_t size) {
    uint32_t sum=0;for(size_t i=0;i<size;i+=4)sum^=be32(p+i);
    return ((sum>>1)^sum)&0x55555555;
}
// Every bit alignment, including sectors crossing the track index. Return
// verified sector count; -1 means conflicting data. had_sync distinguishes a
// non-filesystem protection track from a damaged filesystem track.
int ms_track(const uint8_t* raw,size_t size,int track,uint8_t* output,int* had_sync) {
    if(size<1084)return -2;
    std::vector<uint8_t> extended(raw,raw+size);
    for(size_t i=0;i<1126;++i)extended.push_back(raw[i%size]);
    uint8_t body[1080],info[20],payload[512],check[4];
    unsigned seen=0;int count=0;*had_sync=0;
    uint32_t window=0;
    for(size_t bit=0;bit<size*8+31 && count<11;++bit) {
        window=(window<<1)|((extended[bit/8]>>(7-bit%8))&1);
        if(bit<31 || window!=0x44894489)continue;
        *had_sync=1;
        size_t start=bit+1,byte=start/8;unsigned shift=start%8;
        for(size_t i=0;i<1080;++i)
            body[i]=shift?uint8_t((extended[byte+i]<<shift)|(extended[byte+i+1]>>(8-shift))):extended[byte+i];
        unpack(body,info,4);unpack(body+8,info+4,16);
        if(info[0]!=255 || info[1]!=track || info[2]>=11)continue;
        unpack(body+40,check,4);if(checksum(info,20)!=be32(check))continue;
        unpack(body+56,payload,512);unpack(body+48,check,4);
        if(checksum(payload,512)!=be32(check))continue;
        unsigned sector=info[2];uint8_t* target=output+sector*512;
        if(seen&(1u<<sector)) {if(std::memcmp(target,payload,512))return -1;}
        else {std::memcpy(target,payload,512);seen|=1u<<sector;++count;}
    }
    return count;
}

// Verify one pose against every requested colour identity. Pieces are flattened
// [page,x,y,w,h,offset_x,offset_y,colour_slot]; all dimensions are checked before
// reading. RGBA bytes stay in their original order on either endian host.
int ms_verify_pose(const uint8_t* source,int sw,int sh,int x,int y,int w,int h,
                  const uint8_t* indices,const uint8_t* const* pages,const int* sizes,int page_count,
                  const int* pieces,int piece_count,const uint8_t* colours,int identities) {
    if(sw<=0||sh<=0||w<0||h<0||x<0||y<0||x>sw-w||y>sh-h||identities<1||identities>5)return -1;
    size_t pixels=size_t(w)*h;
    if(pixels>16*1024*1024)return -1;
    std::vector<uint8_t> actual(pixels*4);
    for(int identity=0;identity<identities;++identity) {
        std::fill(actual.begin(),actual.end(),0);
        for(int n=0;n<piece_count;++n) {
            const int* p=pieces+n*8;
            int page=p[0],px=p[1],py=p[2],pw=p[3],ph=p[4],ox=p[5],oy=p[6],slot=p[7];
            if(page<0||page>=page_count||pw<0||ph<0||px<0||py<0||ox<0||oy<0||slot< -1||slot>2 ||
               px>sizes[page*2]-pw||py>sizes[page*2+1]-ph||ox>w-pw||oy>h-ph)return -1;
            for(int j=0;j<ph;++j)for(int i=0;i<pw;++i) {
                const uint8_t* pixel=pages[page]+(size_t(py+j)*sizes[page*2]+px+i)*4;
                if(!pixel[3])continue;
                uint8_t* dest=actual.data()+(size_t(oy+j)*w+ox+i)*4;
                if(dest[3])return -2;
                std::memcpy(dest,slot<0?pixel:colours+(identity*3+slot)*4,4);
            }
        }
        for(int j=0;j<h;++j)for(int i=0;i<w;++i) {
            size_t at=size_t(y+j)*sw+x+i;
            const uint8_t* expected=source+at*4;
            if(indices && indices[at]) {
                if(indices[at]>3)return -1;
                expected=colours+(identity*3+indices[at]-1)*4;
            }
            if(std::memcmp(actual.data()+(size_t(j)*w+i)*4,expected,4))return identity+1;
        }
    }
    return 0;
}
}
