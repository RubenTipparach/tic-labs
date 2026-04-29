pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- hello pico-8
-- by tic-labs

t=0
stars={}
for i=1,40 do
 add(stars,{
  x=rnd(128),
  y=rnd(128),
  s=rnd(1)+0.2,
 })
end

function _update60()
 t+=1
 for s in all(stars) do
  s.x-=s.s
  if s.x<0 then s.x=128 s.y=rnd(128) end
 end
end

function _draw()
 cls(1)
 for s in all(stars) do
  pset(s.x,s.y,s.s>0.8 and 7 or 6)
 end
 local msg="hello pico-8"
 local x=64-#msg*2
 local y=56+sin(t/120)*4
 for i=0,#msg-1 do
  local c=7+(t/4+i)%8
  print(sub(msg,i+1,i+1),x+i*4,y,c)
 end
 print("tic-labs",46,76,6)
 print("\142 z   \151 x",46,96,5)
end
__gfx__
00000000000000000000000000000000
00000000000000000000000000000000
__label__
__gff__
__map__
__sfx__
__music__
