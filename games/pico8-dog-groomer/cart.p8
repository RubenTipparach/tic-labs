pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- dog groomer (stage 1)
-- by tic-labs

cw=4
cgw=14
cgh=8
cox=64-(cgw*cw)\2
coy=68-(cgh*cw)\2

function _init()
 best=0
 round=1
 reset_dog()
end

function reset_dog()
 cells={}
 for gy=0,cgh-1 do
  for gx=0,cgw-1 do
   local nx=(gx-(cgw-1)/2)/((cgw-1)/2)
   local ny=(gy-(cgh-1)/2)/((cgh-1)/2)
   if nx*nx+ny*ny<=1.05 then
    add(cells,{gx=gx,gy=gy,tangle=1+flr(rnd(3))})
   end
  end
 end
 cursor={x=64,y=66}
 tools={"brush"}
 tool=1
 done=false
 cooldown=0
 wag=0
 sparkle=0
end

function _update60()
 wag+=1
 if sparkle>0 then sparkle-=1 end
 if cooldown>0 then cooldown-=1 end
 if done then
  if btnp(4) or btnp(5) then
   round+=1
   reset_dog()
  end
  return
 end
 local sp=1
 if btn(0) then cursor.x-=sp end
 if btn(1) then cursor.x+=sp end
 if btn(2) then cursor.y-=sp end
 if btn(3) then cursor.y+=sp end
 cursor.x=mid(10,cursor.x,118)
 cursor.y=mid(14,cursor.y,118)
 if btnp(5) then tool=tool%#tools+1 end
 if btn(4) and cooldown==0 then
  apply_tool()
  cooldown=4
 end
 local rem=0
 for c in all(cells) do rem+=c.tangle end
 if rem==0 then
  done=true
  if round>best then best=round end
 end
end

function apply_tool()
 local hit=false
 for c in all(cells) do
  local cx=cox+c.gx*cw+2
  local cy=coy+c.gy*cw+2
  local dx=cx-cursor.x
  local dy=cy-cursor.y
  if dx*dx+dy*dy<=49 then
   if tools[tool]=="brush" and c.tangle>0 then
    c.tangle-=1
    hit=true
   end
  end
 end
 if hit then sparkle=6 end
end

function _draw()
 cls(12)
 rectfill(0,108,127,127,4)
 rectfill(8,82,119,108,9)
 line(8,82,119,82,4)
 rectfill(14,108,22,124,4)
 rectfill(105,108,113,124,4)

 rectfill(0,0,127,9,0)
 print("dog groomer",2,2,7)
 print("round "..round,84,2,11)

 rectfill(0,118,127,127,5)
 print("tool:"..tools[tool],3,121,7)
 local rem=0
 for c in all(cells) do rem+=c.tangle end
 print("tangles "..rem,82,121,8)

 draw_dog()
 draw_brush(cursor.x,cursor.y)

 if done then
  rectfill(18,46,109,80,0)
  rect(18,46,109,80,11)
  local m="all brushed!"
  print(m,64-#m*2,52,10)
  print("good dog",48,62,7)
  print("\142 next dog",42,72,6)
 end
end

function draw_dog()
 local bx0,by0=cox-2,coy-2
 local bx1,by1=cox+cgw*cw+1,coy+cgh*cw+1
 ovalfill(bx0+2,by0+5,bx1+2,by1+5,1)
 ovalfill(bx0,by0,bx1,by1,15)

 circfill(cox+20,coy+10,3,4)
 circfill(cox+40,coy+6,2,4)

 rectfill(cox+8,by1-2,cox+12,by1+8,15)
 rect(cox+8,by1-2,cox+12,by1+8,4)
 rectfill(cox+cgw*cw-12,by1-2,cox+cgw*cw-8,by1+8,15)
 rect(cox+cgw*cw-12,by1-2,cox+cgw*cw-8,by1+8,4)

 local hx,hy=bx0-5,by0+8
 circfill(hx,hy,8,15)
 ovalfill(hx-7,hy-9,hx-2,hy-2,4)
 ovalfill(hx+1,hy-10,hx+6,hy-3,4)
 circfill(hx-6,hy+3,3,6)
 circfill(hx-8,hy+2,1,0)
 local blink=(wag\30)%8==0
 if not blink then
  circfill(hx-1,hy-1,1,0)
  pset(hx-1,hy-2,7)
 else
  line(hx-2,hy-1,hx,hy-1,0)
 end
 line(hx-7,hy+5,hx-5,hy+5,0)

 local tx,ty=bx1-1,by0+8
 local sw=sin(wag/40)*2
 line(tx,ty,tx+5,ty-3+sw,15)
 line(tx,ty+1,tx+6,ty-2+sw,15)

 for c in all(cells) do
  local x=cox+c.gx*cw
  local y=coy+c.gy*cw
  if c.tangle>0 then
   local col=14
   if c.tangle>=2 then col=8 end
   if c.tangle>=3 then col=2 end
   rectfill(x,y,x+cw-1,y+cw-1,col)
   pset(x+1,y,0)
   pset(x,y+2,0)
   if c.tangle>=2 then
    pset(x+2,y+1,0)
    pset(x+3,y+3,0)
   end
  end
 end
end

function draw_brush(x,y)
 local hx=x-3
 local hy=y-6
 rectfill(hx,hy,hx+5,hy+1,9)
 rect(hx,hy,hx+5,hy+1,4)
 for i=0,5 do
  line(hx+i,hy+2,hx+i,hy+3+(i%2),7)
 end
 if sparkle>0 then
  circ(x,y,sparkle,10)
 end
 pset(x,y,8)
end

__gfx__
__sfx__
__music__
