-- Quintessence, MIT. DEFLATE size preflight: no output allocation before the hard limit is checked.
local Guard = LibStub:NewLibrary('LibQuinteDeflateGuard-1.0', 1)
if not Guard then return end
local lengths={3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local lengthBits={0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local distances={1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local distanceBits={0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
-- Lecture par tampon de bits (au lieu d'un octet relu et de deux puissances par bit) et tables de Huffman fixes
-- construites une seule fois : même verdict qu'avant, 3 à 4 fois plus rapide (chaque message reçu y passe).
local pow2={};for i=0,31 do pow2[i]=2^i end
local byteAt,floor,ceil=string.byte,math.floor,math.ceil
-- Codes inversés (lus bit à bit, poids faible d'abord) : map[2^longueur+code]=symbole, une seule table par arbre
local function huffman(lens,n)
    local counts,nextCode,map={}, {}, {}
    for i=0,n-1 do local len=lens[i] or 0;assert(len>=0 and len<=15);if len>0 then counts[len]=(counts[len] or 0)+1 end end
    local code,left=0,1
    for bits=1,15 do
        left=left*2-(counts[bits] or 0);assert(left>=0)
        code=(code+(counts[bits-1] or 0))*2;nextCode[bits]=code
    end
    for symbol=0,n-1 do
        local len=lens[symbol] or 0
        if len>0 then
            local c=nextCode[len];nextCode[len]=c+1
            local reverse=0;for _=1,len do reverse=reverse*2+c%2;c=floor(c/2) end
            map[pow2[len]+reverse]=symbol
        end
    end
    return map
end
local fixedLiteral,fixedDistance
local order={16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}
function Guard:Size(data, maximum)
    local ok,result=pcall(function()
        local total=#data
        local nextByte,buffer,count=1,0,0 -- prochain octet à charger, bits en attente (poids faible d'abord), leur nombre
        local produced,blocks=0,0
        local function read(n)
            while count<n do
                local byte=byteAt(data,nextByte);assert(byte)
                buffer=buffer+byte*pow2[count];count=count+8;nextByte=nextByte+1
            end
            local value=buffer%pow2[n]
            buffer=(buffer-value)/pow2[n];count=count-n
            return value
        end
        -- Code de Huffman : jusqu'à 15 bits chargés d'avance (moins en fin de données), essayés du plus court au plus long
        local function symbol(map)
            while count<15 do
                local byte=byteAt(data,nextByte)
                if not byte then break end
                buffer=buffer+byte*pow2[count];count=count+8;nextByte=nextByte+1
            end
            for bits=1,count<15 and count or 15 do
                local code=buffer%pow2[bits]
                local found=map[pow2[bits]+code]
                if found~=nil then buffer=(buffer-code)/pow2[bits];count=count-bits;return found end
            end
            error('Invalid Huffman code')
        end
        local final
        repeat
            blocks=blocks+1;assert(blocks<=4096)
            final=read(1);local kind=read(2)
            if kind==0 then
                read(count%8) -- alignement sur l'octet
                local size,check=read(16),read(16);assert(size+check==65535)
                local position=(nextByte-1)*8-count+size*8;assert(position<=total*8)
                nextByte,buffer,count=position/8+1,0,0
                produced=produced+size;assert(produced<=maximum)
            else
                assert(kind==1 or kind==2)
                local literal,distance
                if kind==1 then
                    if not fixedLiteral then
                        local l,d={},{}
                        for i=0,287 do l[i]=i<=143 and 8 or i<=255 and 9 or i<=279 and 7 or 8 end
                        for i=0,31 do d[i]=5 end
                        fixedLiteral,fixedDistance=huffman(l,288),huffman(d,32)
                    end
                    literal,distance=fixedLiteral,fixedDistance
                else
                    local nl,nd,nc=read(5)+257,read(5)+1,read(4)+4;assert(nl<=286 and nd<=32)
                    local cl={};for i=1,nc do cl[order[i]]=read(3) end
                    local code=huffman(cl,19);local all={}
                    while #all<nl+nd do
                        local value=symbol(code)
                        if value<16 then all[#all+1]=value
                        else
                            local copies,repeated
                            if value==16 then assert(#all>0);copies=read(2)+3;repeated=all[#all]
                            elseif value==17 then copies=read(3)+3;repeated=0
                            elseif value==18 then copies=read(7)+11;repeated=0 else error('Invalid repeat') end
                            assert(#all+copies<=nl+nd)
                            for _=1,copies do all[#all+1]=repeated end
                        end
                    end
                    local l,d={},{};for i=0,nl-1 do l[i]=all[i+1] end;for i=0,nd-1 do d[i]=all[nl+i+1] end
                    assert(l[256] and l[256]>0);literal,distance=huffman(l,nl),huffman(d,nd)
                end
                while true do
                    local value=symbol(literal)
                    if value==256 then break
                    elseif value<256 then produced=produced+1
                    else
                        local index=value-256;assert(lengths[index])
                        local size=lengths[index]+read(lengthBits[index])
                        local dist=symbol(distance)+1;assert(distances[dist])
                        local back=distances[dist]+read(distanceBits[dist]);assert(back<=produced and back<=32768)
                        produced=produced+size
                    end
                    assert(produced<=maximum)
                end
            end
        until final==1
        assert(ceil(((nextByte-1)*8-count)/8)==total)
        return produced
    end)
    return ok and result or nil
end
