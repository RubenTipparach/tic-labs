# Software 3D Rendering on TIC-80

Research notes on how to build a general 3D software rasterizer, with a focus
on what TIC-80 (the fantasy console) gives you out of the box and what you have
to implement in Lua yourself.

TIC-80 has a 240x136 framebuffer and a 16-colour palette. It ships with two
built-in textured-triangle primitives (`textri` / `ttri`) that cover the
pixel-filling part of the pipeline, so most real TIC-80 "3D engines" are just
vertex transform + culling + clipping + depth sorting on top of those.

Sections:

1. What TIC-80 gives you: `textri` and `ttri`
2. The rendering pipeline at a glance
3. Perspective projection
4. Clip-space culling and triangle clipping
5. Backface culling
6. Bounding-box / frustum culling
7. Triangle rasterization with edge functions and barycentrics
8. Depth buffer (z-buffer)
9. Perspective-correct texture mapping
10. Case study: FPS80 / ticgeo3d
11. Camera and `lookAt` matrices
12. Shading: flat and Gouraud
13. Depth sorting / painter's algorithm
14. TIC-80 Lua performance tips
15. Further reading

---

## 1. What TIC-80 gives you: `textri` and `ttri`

TIC-80 exposes two built-in textured triangle primitives. They handle the
inner rasterization loop in C, which is important because a pure-Lua inner
loop per pixel is far too slow for anything non-trivial on a fantasy console.

### `textri` (older)

```
textri(x1, y1, x2, y2, x3, y3,
       u1, v1, u2, v2, u3, v3,
       [use_map=false], [trans=-1])
```

- `(x1,y1)..(x3,y3)` are screen-space vertex positions.
- `(u1,v1)..(u3,v3)` are texel coordinates. The whole sprite sheet (or map) is
  treated as one big image, so u=16,v=0 is the top-left of sprite #2.
- `use_map`: read texture from MAP RAM instead of SPRITES RAM.
- `trans`: colour key (or array of colour keys on 0.80+).

Critical caveat from the wiki: **`textri` does not perform perspective
correction**, so it is generally unsuitable for real 3D — triangles whose
vertices have different depths will swim with affine-texture-mapping
artifacts (the classic PS1 warping look, which you may actually want).

Minimal wiki demo:

```lua
-- title:  triangle demo
-- author: MonstersGoBoom
-- script: lua
usize, vsize = 32, 32
function TIC()
  cls(1)
  if btn(0) then usize=usize-1 end
  if btn(1) then usize=usize+1 end
  if btn(2) then vsize=vsize-1 end
  if btn(3) then vsize=vsize+1 end

  textri(0,0, 64,0, 0,64,   0,0, usize,0, 0,vsize,     true, 14)
  textri(64,0, 0,64, 64,64, usize,0, 0,vsize, usize,vsize, true, 14)
end
```

### `ttri` (newer, 3D-aware)

```
ttri(x1, y1, x2, y2, x3, y3,
     u1, v1, u2, v2, u3, v3,
     [texsrc=0], [chromakey=-1],
     [z1=0], [z2=0], [z3=0])
```

Key differences:

- `texsrc`: 0 = TILES, 1 = MAP, 2 = opposite VBANK screen (lets you use a
  second 240x136 surface as a texture atlas).
- `z1, z2, z3`: **when you pass these, `ttri` does perspective-correct texture
  interpolation AND uses a depth buffer**. `cls()` clears the depth buffer.

This is the primitive you want for any real 3D work on TIC-80. It means you
can get away with *not* writing the rasterizer itself — you "only" have to
feed it correctly transformed, clipped and culled triangles with a `1/z`-like
depth value per vertex.

Sources:
- [TIC-80 wiki: textri](https://github.com/nesbox/TIC-80/wiki/textri)
- [TIC-80 wiki: ttri](https://github.com/nesbox/TIC-80/wiki/ttri)
- [Issue #612: perspective-corrected textri](https://github.com/nesbox/TIC-80/issues/612)

---

## 2. The rendering pipeline at a glance

Even when `ttri` is doing the pixel work, you still need a pipeline:

```
 model verts
      |  model matrix
      v
 world verts
      |  view matrix (camera)
      v
 view-space (camera-space) verts  <-- backface cull here, frustum cull AABBs here
      |  projection matrix
      v
 clip-space verts (x, y, z, w)    <-- clip against w-planes here
      |  divide by w
      v
 NDC verts (x/w, y/w, z/w)
      |  viewport transform
      v
 screen-space verts (sx, sy, depth)
      |
      v
 rasterizer (textri / ttri, or your own edge-function loop)
```

On TIC-80 you usually collapse view+projection into a single matrix or, like
FPS80, hard-code the whole thing as one function to save Lua math calls.

---

## 3. Perspective projection

A standard perspective projection matrix (right-handed, looking down -Z):

```
 [ f/aspect   0        0                      0                    ]
 [ 0          f        0                      0                    ]
 [ 0          0   (far+near)/(near-far)  (2*far*near)/(near-far)    ]
 [ 0          0       -1                      0                    ]

 where f = 1 / tan(fovY / 2)
```

After multiplying `(x, y, z, 1)` by this you get homogeneous clip space
`(x_c, y_c, z_c, w_c)`. The divide-by-w step gives you NDC coordinates in
`[-1, 1]`, and the viewport transform maps NDC to pixels.

FPS80 pre-bakes everything into one function and skips matrices entirely:

```lua
function S3Proj(x, y, z)
  local c, s, a, b = S3.cosMy, S3.sinMy, S3.termA, S3.termB
  local px = 0.9815*c*x + 0.9815*s*z + 0.9815*a
  local py = 1.7321*y   - 1.7321*S3.ey
  local pz =      s*x   - z*c - b - 0.2
  local pw =      x*s   - z*c - b
  local ndcx, ndcy = px/abs(pw), py/abs(pw)
  return 120 + ndcx*120, 68 - ndcy*68, pz
end
```

Note how `px/py` are divided by `abs(pw)`, not `pw`. That's because the
engine already knows it only needs yaw rotation and always has objects in
front of the camera — so it can avoid a full homogeneous clip.

For a general-purpose engine you want the real divide-by-w, because clipping
against the near plane must happen *before* the divide, on the
`(x_c, y_c, z_c, w_c)` coordinates — otherwise vertices that cross behind the
camera produce +/- infinity and the triangle folds inside out.

Sources:
- [scratchapixel — perspective projection](https://www.scratchapixel.com/lessons/3d-basic-rendering/perspective-and-orthographic-projection-matrix.html)
- [FPS80 article](https://medium.com/@btco_code/writing-a-retro-3d-fps-engine-from-scratch-b2a9723e6b06)

---

## 4. Clip-space culling and triangle clipping

The safest place to clip a triangle is in **homogeneous clip space**, before
the perspective divide. Each vertex `v = (x, y, z, w)` is inside the frustum
when all six inequalities hold:

```
-w <= x <= w
-w <= y <= w
-w <= z <= w   (OpenGL convention; D3D uses 0 <= z <= w)
```

### Trivial reject / trivial accept

Compute six "out-codes" per vertex (one bit per plane). If the bitwise AND of
all three vertex out-codes is non-zero, every vertex is outside the same
plane — reject the whole triangle. If the bitwise OR is zero, every vertex is
inside every plane — accept it unchanged.

### Sutherland-Hodgman polygon clipping

When a triangle straddles a plane, you split it. Sutherland-Hodgman clips a
polygon against one plane at a time, building up an output polygon:

```text
input  = [v0, v1, v2]
for each plane p in {left, right, bottom, top, near, far}:
    output = []
    for each edge (A -> B) in input:
        A_in = inside(A, p)
        B_in = inside(B, p)
        if A_in and B_in:
            output.append(B)
        elif A_in and not B_in:
            output.append(intersect(A, B, p))
        elif not A_in and B_in:
            output.append(intersect(A, B, p))
            output.append(B)
        # else: both outside, emit nothing
    input = output
```

A triangle clipped against all six planes can produce up to 9 vertices,
which you then re-triangulate as a fan.

The only plane you *must* clip against is the near plane — the others are
handled implicitly if your rasterizer clips to the screen bounding box (which
TIC-80's `ttri` already does).

Near-plane clip of a single edge in homogeneous space:

```lua
-- clip edge (a -> b) against plane z = -w (OpenGL near plane)
local function intersectNear(a, b)
  -- signed distance to the plane
  local da = a.z + a.w
  local db = b.z + b.w
  local t  = da / (da - db)
  return {
    x = a.x + t*(b.x - a.x),
    y = a.y + t*(b.y - a.y),
    z = a.z + t*(b.z - a.z),
    w = a.w + t*(b.w - a.w),
    -- interpolate any vertex attributes (UV, colour) by the same t
    u = a.u + t*(b.u - a.u),
    v = a.v + t*(b.v - a.v),
  }
end
```

Sources:
- [Sutherland-Hodgman (Wikipedia)](https://en.wikipedia.org/wiki/Sutherland%E2%80%93Hodgman_algorithm)
- [Blinn & Newell — clipping in homogeneous coordinates (1978)](https://dl.acm.org/doi/pdf/10.1145/965139.807398)
- [Chaos in Motion — 3D clipping in homogeneous coordinates](https://chaosinmotion.com/2016/05/22/3d-clipping-in-homogeneous-coordinates/)

---

## 5. Backface culling

Roughly half of the triangles of a closed mesh face away from the camera.
You can skip them for free.

### Method A: normal dot product (world/view space)

```lua
local function backfacing(v0, v1, v2, camPos)
  -- two edge vectors, then cross product = face normal
  local ax, ay, az = v1.x-v0.x, v1.y-v0.y, v1.z-v0.z
  local bx, by, bz = v2.x-v0.x, v2.y-v0.y, v2.z-v0.z
  local nx = ay*bz - az*by
  local ny = az*bx - ax*bz
  local nz = ax*by - ay*bx
  -- view vector from camera to a vertex
  local vx, vy, vz = v0.x-camPos.x, v0.y-camPos.y, v0.z-camPos.z
  return (nx*vx + ny*vy + nz*vz) >= 0
end
```

### Method B: signed area in screen space (winding order)

This is the one modern GPUs actually use. Once you have screen-space
positions, compute:

```lua
local function signedArea2D(a, b, c)
  return (b.x - a.x) * (c.y - a.y)
       - (b.y - a.y) * (c.x - a.x)
end
```

If you define front-facing as counter-clockwise (the typical choice), cull
when `signedArea2D < 0`. No normal needed, no dot product, no matrices — and
it's the same determinant your rasterizer will reuse as an edge function, so
it's essentially free.

Sources:
- [Back-face culling (Wikipedia)](https://en.wikipedia.org/wiki/Back-face_culling)
- [LearnOpenGL — face culling](https://learnopengl.com/Advanced-OpenGL/Face-culling)

---

## 6. Bounding-box / frustum culling

Before you even transform a mesh's vertices you can reject whole objects
cheaply with an AABB (axis-aligned bounding box) test against the camera
frustum.

### Frustum planes from a view-projection matrix

Given the combined matrix `M = P * V`, the six frustum plane equations (in
the form `ax + by + cz + d = 0`) fall out as sums/differences of the matrix
rows:

```
left   =  row3 + row0
right  =  row3 - row0
bottom =  row3 + row1
top    =  row3 - row1
near   =  row3 + row2
far    =  row3 - row2
```

Each plane should be normalized so `|(a,b,c)| = 1`.

### Plane-vs-AABB test ("p-vertex" trick)

For every plane, pick the AABB corner most in the direction of the plane's
normal. If that "positive vertex" is still behind the plane, the whole box is
behind the plane and you can reject the object. This is ~6x faster than
testing all 8 corners:

```lua
local function aabbInFrustum(bmin, bmax, planes)
  for i = 1, 6 do
    local p = planes[i]
    -- positive vertex: the corner furthest along the plane normal
    local px = p.a >= 0 and bmax.x or bmin.x
    local py = p.b >= 0 and bmax.y or bmin.y
    local pz = p.c >= 0 and bmax.z or bmin.z
    if p.a*px + p.b*py + p.c*pz + p.d < 0 then
      return false  -- completely outside this plane
    end
  end
  return true
end
```

For a TIC-80-scale engine you'd usually group meshes into chunks and cull at
the chunk level, then only re-test visible chunks at the triangle level.

Sources:
- [ktstephano — View frustum culling with AABBs](https://ktstephano.github.io/rendering/stratusgfx/aabbs)
- [Bruno Opsenica — frustum culling](https://bruop.github.io/frustum_culling/)
- [Assarsson & Möller — optimized VFC algorithms (PDF)](https://www.cse.chalmers.se/~uffe/vfc_bbox.pdf)
- [ryg blog — view frustum culling](https://fgiesen.wordpress.com/2010/10/17/view-frustum-culling/)

---

## 7. Triangle rasterization with edge functions and barycentrics

This is what you'd write if you were rolling your own rasterizer (e.g. on a
platform without a `ttri` primitive, or if you need custom per-pixel effects
that `ttri` can't do).

### The edge function

The signed area of the parallelogram formed by two 2D vectors is a 2x2
determinant:

```c
int orient2d(Point2D a, Point2D b, Point2D c) {
    return (b.x - a.x) * (c.y - a.y)
         - (b.y - a.y) * (c.x - a.x);
}
```

`orient2d(a, b, p)` tells you which side of line `a->b` the point `p` is on
(positive = left, negative = right, zero = on the line). Evaluating this for
all three edges at a pixel gives you three numbers `(w0, w1, w2)`. If all
three are non-negative (or all non-positive, depending on winding), the
pixel is inside the triangle. Those same three numbers, divided by the
total triangle area, **are the barycentric coordinates**:

```
lambda0 = w0 / area
lambda1 = w1 / area
lambda2 = w2 / area
```

### The basic loop (bounding-box rasterizer)

From Fabian "ryg" Giesen's excellent article:

```c
void drawTri(Point2D v0, Point2D v1, Point2D v2) {
    int minX = max(min3(v0.x, v1.x, v2.x), 0);
    int minY = max(min3(v0.y, v1.y, v2.y), 0);
    int maxX = min(max3(v0.x, v1.x, v2.x), screenW - 1);
    int maxY = min(max3(v0.y, v1.y, v2.y), screenH - 1);

    Point2D p;
    for (p.y = minY; p.y <= maxY; p.y++) {
        for (p.x = minX; p.x <= maxX; p.x++) {
            int w0 = orient2d(v1, v2, p);
            int w1 = orient2d(v2, v0, p);
            int w2 = orient2d(v0, v1, p);
            if ((w0 | w1 | w2) >= 0)  // all same sign
                renderPixel(p, w0, w1, w2);
        }
    }
}
```

### Incremental evaluation

The whole point of edge functions is that they're linear in `p`, so you can
step them by simple adds inside the inner loop:

```
w_row = w(minX, minY)
for y in rows:
    w = w_row
    for x in cols:
        if (w0 | w1 | w2) >= 0: shade pixel
        w += dwdx       -- one add per pixel, per edge
    w_row += dwdy       -- one add per row, per edge
```

Where `dwdx = (b.y - a.y)` and `dwdy = -(b.x - a.x)` for edge `a -> b`.

### The top-left fill rule

When two triangles share an edge, you want each pixel on that edge to be
drawn by **exactly one** of them, not both (overdraw) and not neither
(cracks). Standard convention: a pixel on an edge belongs to the triangle if
the edge is a *top* or *left* edge.

```c
// Bias the edge functions by -1 if the edge is NOT a top-left edge,
// so that a zero result on those edges becomes a rejection.
int bias0 = isTopLeft(v1, v2) ? 0 : -1;
int bias1 = isTopLeft(v2, v0) ? 0 : -1;
int bias2 = isTopLeft(v0, v1) ? 0 : -1;

int w0 = orient2d(v1, v2, p) + bias0;
int w1 = orient2d(v2, v0, p) + bias1;
int w2 = orient2d(v0, v1, p) + bias2;

if ((w0 | w1 | w2) >= 0)
    renderPixel(p, w0, w1, w2);
```

A "top edge" is exactly horizontal and points left; a "left edge" is any
edge that goes downward.

Sources:
- [ryg — Triangle rasterization in practice](https://fgiesen.wordpress.com/2013/02/08/triangle-rasterization-in-practice/)
- [scratchapixel — the rasterization stage](https://www.scratchapixel.com/lessons/3d-basic-rendering/rasterization-practical-implementation/rasterization-stage.html)
- [Salem Haykal — An optimized triangle rasterizer (PDF)](https://www.digipen.edu/sites/default/files/public/docs/theses/salem-haykal-digipen-master-of-science-in-computer-science-thesis-an-optimized-triangle-rasterizer.pdf)

---

## 8. Depth buffer (z-buffer)

A depth buffer stores, for every pixel, the depth of the closest fragment
drawn so far. Before writing a new pixel, compare its depth; only overwrite
if the new fragment is nearer.

```lua
-- pseudo-code, inside your per-pixel loop
local depth = lambda0*z0 + lambda1*z1 + lambda2*z2
local idx   = y*W + x
if depth < zbuffer[idx] then
  zbuffer[idx]  = depth
  framebuffer[idx] = shade(...)
end
```

Two important details:

1. **Interpolate `1/z`, not `z`.** Linear interpolation in screen space is
   correct for `1/z` but not for `z`. In practice most software rasterizers
   store depth as `1/w` and compare "bigger is nearer", or store `z/w` and
   compare "smaller is nearer" — both are linear in screen space.

2. **Resolution.** A 16-bit integer depth buffer is usually fine for a tiny
   resolution like 240x136. You want more precision near the camera than
   far from it, which is why hardware uses `1/w`-style depth.

### TIC-80 specifics

You don't have to build a depth buffer from scratch: **`ttri` implements
one internally whenever you pass `z1, z2, z3`**. The wiki says:

> A depth buffer is implemented in `ttri` when `z1, z2, z3` arguments are
> set. The depth buffer can be cleared using the `cls()` function.

So the TIC-80 recipe is: project your vertices yourself, compute a `z` for
each (typically `1/w` after the projection matrix), and pass those into
`ttri`. The fantasy console takes care of per-pixel depth compare.

Sources:
- [scratchapixel — the z-buffer algorithm](https://www.scratchapixel.com/lessons/3d-basic-rendering/rasterization-practical-implementation/visibility-problem-depth-buffer-depth-interpolation.html)
- [Z-buffering (Wikipedia)](https://en.wikipedia.org/wiki/Z-buffering)
- [TIC-80 wiki: ttri](https://github.com/nesbox/TIC-80/wiki/ttri)

---

## 9. Perspective-correct texture mapping

The problem: screen-space linear interpolation of UVs produces the wobbling
textures you see on PS1 games. Equidistant points in 3D don't project to
equidistant points in screen space, so `u = lambda0*u0 + lambda1*u1 + lambda2*u2`
is **wrong** once the triangle has depth variation.

The trick, from Heckbert/Moreton and everyone since:

> Interpolate `u/z, v/z, 1/z` linearly in screen space, then divide at each
> pixel.

```lua
-- preprocess: per vertex
local inv_z = 1 / z
local u_over_z = u * inv_z
local v_over_z = v * inv_z

-- per pixel (after computing barycentrics lambda0/1/2)
local inv_z_p = l0*inv_z0  + l1*inv_z1  + l2*inv_z2
local u_over_z_p = l0*u_over_z0 + l1*u_over_z1 + l2*u_over_z2
local v_over_z_p = l0*v_over_z0 + l1*v_over_z1 + l2*v_over_z2

local u = u_over_z_p / inv_z_p
local v = v_over_z_p / inv_z_p
```

The per-pixel divide is what makes this expensive in software. A common
optimization is to do the correct divide only every N pixels (e.g. every 8
or 16) and linearly interpolate between the correction points — this is the
"sub-affine" mapper the Quake engine used.

Again: on TIC-80 you get this for free from `ttri` when you pass z-values,
so you don't have to implement it. But it's worth understanding what the
primitive is doing, because bad `z` values in equal `1/z` mean bad texture
mapping.

Sources:
- [scratchapixel — perspective-correct interpolation](https://www.scratchapixel.com/lessons/3d-basic-rendering/rasterization-practical-implementation/perspective-correct-interpolation-vertex-attributes.html)
- [Chris Hecker — Perspective Texture Mapping (Game Developer Magazine series)](https://www.chrishecker.com/Miscellaneous_Technical_Articles)

---

## 10. Case study: FPS80 / ticgeo3d

[FPS80](https://github.com/btco/ticgeo3d) by Bruno Oliveira is the best real
example of a hand-written 3D engine on TIC-80. It's worth studying because
it shows which corners you can cut for a constrained platform.

Self-imposed constraints (and why they matter):

- **Flat levels**, uniform floor/ceiling heights → every screen column has
  at most one wall, so overdraw is zero and you can render to a 1D
  "H-buffer" keyed by X.
- **Camera has only yaw** (no pitch/roll) → the projection collapses into a
  single hard-coded function (shown in section 3 above).
- **Entities are billboards** → they never need 3D triangles, only axis
  aligned sprites with depth.
- **Point lights only** → no per-pixel normals, shading is table-driven.

Horizontal buffer idea:

```lua
function _S3RendHbuf(hbuf)
  for x = startx, endx, step do
    local hb = hbuf[x+1]
    local w  = hb.wall
    if w then
      local z = _S3Interp(w.slx, w.slz, w.srx, w.srz, x)
      local u = _S3PerspTexU(w, x)
      _S3RendTexCol(w.tid, x, hb.ty, hb.by, u, z, ...)
    end
  end
end
```

Other tricks from the writeup:

- **Interleaved columns**: render only even X on even frames and odd X on
  odd frames. Halves fill rate for a retro flicker look.
- **Pre-baked floor depth**: one formula `z = 3000 / (y - 68)` instead of
  per-pixel transform.
- **Colour ramps + dithering**: the 16-colour palette is divided into 3
  ramps of 4 brightness levels each, with dithering for in-between shades.
- **Stencil buffer**: entities written front-to-back with a stencil mask to
  avoid overdraw.

Source:
- [btco/ticgeo3d on GitHub](https://github.com/btco/ticgeo3d)
- [Writing a retro 3D FPS engine from scratch — Medium](https://medium.com/@btco_code/writing-a-retro-3d-fps-engine-from-scratch-b2a9723e6b06)

### Other TIC-80 3D projects

- [AXES — a portable 3D Lua library](https://tic80.com/play?cart=232) — wraps
  `textri`/`ttri` with a matrix stack and mesh loader.
- [3D Demo for TIC-80 (Nopy)](https://nopy.itch.io/3d-demo) — unfinished Lua
  software rasterizer, useful as a reference for what *not* to do in pure
  Lua.
- [3D CUBE TEST cart](https://tic80.com/play?cart=2570) — minimal `ttri`
  example.

---

## 11. Camera and `lookAt` matrices

The view matrix transforms world-space vertices into camera-space (with the
camera at the origin, looking down -Z). The cleanest way to build it is a
`lookAt` function — you give it a camera position, a target to look at, and
an "up" reference vector, and it returns the inverse-camera matrix.

```lua
-- normalise a 3-vector
local function norm(x, y, z)
  local len = math.sqrt(x*x + y*y + z*z)
  return x/len, y/len, z/len
end

local function cross(ax, ay, az, bx, by, bz)
  return ay*bz - az*by,
         az*bx - ax*bz,
         ax*by - ay*bx
end

-- Build a view matrix (row-major 4x4) that puts the camera at `eye`
-- looking at `target`, with world-up `up`.
local function lookAt(eye, target, up)
  -- forward = normalize(eye - target)   (points away from target)
  local fx, fy, fz = norm(eye.x-target.x, eye.y-target.y, eye.z-target.z)
  -- right = normalize(cross(up, forward))
  local rx, ry, rz = cross(up.x,up.y,up.z, fx,fy,fz)
  rx, ry, rz = norm(rx, ry, rz)
  -- true up = cross(forward, right)
  local ux, uy, uz = cross(fx,fy,fz, rx,ry,rz)

  -- translation = -eye in the camera basis
  local tx = -(rx*eye.x + ry*eye.y + rz*eye.z)
  local ty = -(ux*eye.x + uy*eye.y + uz*eye.z)
  local tz = -(fx*eye.x + fy*eye.y + fz*eye.z)

  return {
    rx, ry, rz, tx,
    ux, uy, uz, ty,
    fx, fy, fz, tz,
    0,  0,  0,  1,
  }
end
```

Key points:

- The three basis rows are `right`, `up`, `forward`. That's because the
  view matrix is the *inverse* of the camera's world transform, and for a
  pure rotation the inverse is the transpose.
- The translation column is `-eye` expressed in the camera basis, not just
  `-eye`.
- Convention matters: if you want `+Z` to be "into the screen" (D3D-style),
  flip the forward axis and swap the cross-product operands accordingly.
- Combine with projection as `clip = P * V * model * vertex`. Most TIC-80
  engines precompute `PV` once per frame and only multiply per-model the
  model matrix.

Sources:
- [scratchapixel — placing a camera with lookAt](https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/lookat-function.html)
- [LearnOpenGL — camera](https://learnopengl.com/Getting-started/Camera)

---

## 12. Shading: flat and Gouraud

The minimum-viable lighting model is **Lambert diffuse**: a surface's
brightness is proportional to `max(0, dot(N, L))`, where `N` is the surface
normal and `L` is the direction *to* the light.

### Flat shading

Compute one colour per triangle (using the face normal) and feed it as a
solid fill. On TIC-80 this is very cheap: one dot product per triangle,
then pick a palette index from a brightness ramp.

```lua
-- flat Lambert: one brightness value for the whole triangle
local function flatShade(v0, v1, v2, lightDir, baseColour)
  -- face normal from two edge vectors
  local ax, ay, az = v1.x-v0.x, v1.y-v0.y, v1.z-v0.z
  local bx, by, bz = v2.x-v0.x, v2.y-v0.y, v2.z-v0.z
  local nx, ny, nz = ay*bz-az*by, az*bx-ax*bz, ax*by-ay*bx
  -- normalise
  local ilen = 1 / math.sqrt(nx*nx + ny*ny + nz*nz)
  nx, ny, nz = nx*ilen, ny*ilen, nz*ilen

  local ndotl = nx*lightDir.x + ny*lightDir.y + nz*lightDir.z
  if ndotl < 0 then ndotl = 0 end

  -- pick a palette index from a 4-level ramp
  local shade = math.floor(ndotl * 3 + 0.5)  -- 0..3
  return baseColour[shade + 1]
end
```

### Gouraud shading

Compute lighting at each *vertex* using a per-vertex normal (usually the
average of the face normals of the triangles that share that vertex), then
let the rasterizer linearly interpolate the brightness across the triangle.
On TIC-80 you can't pass a per-vertex colour to `ttri`, so "real" Gouraud
isn't directly supported — but you can fake it by:

- splitting the triangle into smaller triangles and feeding `ttri` different
  UVs into a pre-baked ramp texture, or
- drawing flat-shaded sub-triangles with slightly different palette indices
  along a gradient.

### Phong shading

Per-pixel normal interpolation. Too expensive for pure Lua. Skip.

### TIC-80 specific trick: palette swap instead of math

Because the console has only 16 colours, most 3D carts pre-build 3–4 colour
ramps (e.g. 4 shades of grey, 4 shades of green, 4 shades of brown) and
store the "brightness index" 0..3 per triangle. Shading then becomes:

```lua
-- no multiplies: (ramp << 2) | brightness
local paletteIndex = ramp*4 + brightness
```

FPS80 uses exactly this scheme (see section 10).

Sources:
- [LearnOpenGL — basic lighting (Lambert)](https://learnopengl.com/Lighting/Basic-Lighting)
- [Wikipedia — Gouraud shading](https://en.wikipedia.org/wiki/Gouraud_shading)

---

## 13. Depth sorting / painter's algorithm

Before `ttri` had a depth buffer, the standard TIC-80 trick for hidden
surface removal was the **painter's algorithm**: sort all triangles
back-to-front and draw them in that order. Whatever you draw last wins.

```lua
-- very simple depth key: average z of the three vertices
local function triDepth(t)
  return (t.v0.z + t.v1.z + t.v2.z) * (1/3)
end

table.sort(triangles, function(a, b)
  return triDepth(a) > triDepth(b)  -- far ones first
end)

for _, t in ipairs(triangles) do
  ttri(t.x1, t.y1, t.x2, t.y2, t.x3, t.y3,
       t.u1, t.v1, t.u2, t.v2, t.u3, t.v3,
       0, -1)  -- no z args = no depth buffer
end
```

### Pros

- Dirt simple. Works fine for small meshes and static scenes.
- Lets you use `ttri` *without* z-values, which is slightly faster.
- You can mix translucent triangles into the sort naturally.

### Cons (this is why z-buffers exist)

- **Cyclic overlap**: three triangles A, B, C where A is in front of B, B
  in front of C, and C in front of A. No linear ordering is correct. Fix
  is to split (clip) one of them — annoying.
- **Piercing**: two triangles that actually intersect. Same deal: you have
  to cut them along the intersection line.
- **Sorting cost**: `O(n log n)` per frame. For ~200 triangles that's fine;
  for thousands, not so much.
- **Average-z is lossy**: a long triangle with one vertex close and two far
  can "lose" to a much farther triangle when sorted by centroid.

In practice, the TIC-80 rule of thumb:

- Fewer than ~100 opaque triangles per frame, no weird overlaps: painter's
  algorithm is fine.
- More than that, or dynamic geometry, or overlapping meshes: pass z-values
  to `ttri` and let the depth buffer sort it out.
- Translucent triangles: always sort back-to-front, then draw *after* all
  opaque geometry, with depth testing on but depth writes off.

Sources:
- [Painter's algorithm (Wikipedia)](https://en.wikipedia.org/wiki/Painter%27s_algorithm)
- [LearnWebGL — hidden surface removal](http://learnwebgl.brown37.net/11_advanced_rendering/hidden_surface_removal.html)

---

## 14. TIC-80 Lua performance tips

The rasterizer is in C, but every frame you're still running Lua over
hundreds of vertices and triangles. A few rules make a huge difference.

### Localize everything in hot loops

Global lookups in Lua go through a hash table; local reads are a register
fetch. At the top of any hot function:

```lua
local ttri   = ttri
local sin    = math.sin
local cos    = math.cos
local floor  = math.floor
local sqrt   = math.sqrt
local tinsert = table.insert
```

Rule of thumb: if you reference a global more than once inside a loop,
make it a local first. This alone can be a 2-4x speedup.

### Don't allocate inside the inner loop

Every `{}` and every `"foo"..x` is garbage collector pressure. Pre-allocate
vertex/triangle pools and recycle them:

```lua
-- bad: allocates per triangle per frame
for i = 1, #mesh do
  local v = { x = mesh[i].x * s, y = mesh[i].y * s, z = mesh[i].z * s }
  ...
end

-- good: mutate a fixed scratch buffer
local scratch = {}
for i = 1, #mesh do
  local s = scratch[i] or {}
  scratch[i] = s
  s.x = mesh[i].x * sx
  s.y = mesh[i].y * sy
  s.z = mesh[i].z * sz
end
```

### Use numeric-indexed arrays, not string keys

`v[1], v[2], v[3]` is faster than `v.x, v.y, v.z` in Lua — array-part
access is O(1) with no hash. For vector-heavy code this is a real win.

### Batch screen writes with `memcpy` / `poke4`

If you ever need to touch the framebuffer directly (for e.g. a sky
gradient or a flat horizon), write 4 pixels at a time using `poke4` or
clear regions with `memcpy`/`memset`:

```lua
-- clear the top half of the screen to palette index 12
memset(0x00000, 0xcc, 240*68/2)  -- 2 pixels per byte
```

Framebuffer is at `0x00000`, 4 bits per pixel, so one byte holds two
adjacent pixels.

### `vbank(1)` as a second working surface

TIC-80 has two 240x136 video banks. Typical uses:

- Render 3D to `vbank(0)` and HUD to `vbank(1)`, blit in `OVR()`.
- Use `vbank(1)` as a **texture atlas**: pass `texsrc = 2` to `ttri` and
  you get an entire 240x136 image to sample from, on top of the normal
  sprite sheet.
- Build a per-frame lightmap or fog LUT in `vbank(1)` and read it back.

### Other small wins

- Pre-build sin/cos tables instead of calling `math.sin`/`math.cos` per
  vertex.
- Replace `math.floor(x + 0.5)` with `x | 0` (bitwise `or` with 0 truncates
  in Lua 5.3+).
- Avoid `ipairs` in tight loops — `for i = 1, #t do` is faster.
- `table.sort` is fine for a few hundred elements per frame; beyond that,
  radix / bucket sort is worth writing.
- Use the MOOCOW profiler / `time()` diffs to actually measure, not guess.

Sources:
- [Roberto Ierusalimschy — Lua Performance Tips (PDF)](https://www.lua.org/gems/sample.pdf)
- [TIC-80 /learn — memory map](https://tic80.com/learn)
- [TIC-80 Cheat Sheet](https://skyelynwaddell.github.io/tic80-manual-cheatsheet/)

---

## 15. Further reading

Core references this doc leans on:

- [scratchapixel — 3D Basic Rendering](https://www.scratchapixel.com/lessons/3d-basic-rendering/rasterization-practical-implementation/rasterization-stage.html) — full pipeline, both theoretical and practical.
- [ryg blog — Triangle rasterization in practice](https://fgiesen.wordpress.com/2013/02/08/triangle-rasterization-in-practice/) and the rest of [ryg's rasterization series](https://fgiesen.wordpress.com/category/graphics/).
- [Trenki's Dev Blog — developing a software renderer](https://trenki2.github.io/blog/2017/06/06/developing-a-software-renderer-part1/) — C++ series that builds a complete software rasterizer.
- [David Rousset — 3D software engine tutorial part 4: rasterization & z-buffering](https://www.davrous.com/2013/06/21/tutorial-part-4-learning-how-to-write-a-3d-software-engine-in-c-ts-or-js-rasterization-z-buffering/) — JS/TS-friendly walk-through.

TIC-80 specific:

- [TIC-80 on GitHub](https://github.com/nesbox/TIC-80)
- [TIC-80 wiki: textri](https://github.com/nesbox/TIC-80/wiki/textri)
- [TIC-80 wiki: ttri](https://github.com/nesbox/TIC-80/wiki/ttri)
- [TIC-80 /learn](https://tic80.com/learn)
- [awesome-tic-80](https://github.com/stefandevai/awesome-tic-80)

Adjacent topics you'll eventually want:

- [Back-face culling (Wikipedia)](https://en.wikipedia.org/wiki/Back-face_culling)
- [Sutherland-Hodgman polygon clipping (Wikipedia)](https://en.wikipedia.org/wiki/Sutherland%E2%80%93Hodgman_algorithm)
- [ktstephano — AABB frustum culling](https://ktstephano.github.io/rendering/stratusgfx/aabbs)
- [Bruno Opsenica — improved frustum culling](https://bruop.github.io/improved_frustum_culling/)
- [Z-buffering (Wikipedia)](https://en.wikipedia.org/wiki/Z-buffering)

---

## TL;DR checklist for a TIC-80 3D engine

- [ ] Build view matrix with `lookAt(eye, target, up)`, precompute `PV`
      once per frame.
- [ ] Model -> World -> View transform (precomputed matrices, or hard-coded
      per-game like FPS80).
- [ ] Object-level AABB vs frustum culling.
- [ ] Projection into homogeneous clip space.
- [ ] Near-plane clip in clip space (Sutherland-Hodgman, one plane is enough
      if the rasterizer clips to the viewport).
- [ ] Perspective divide -> viewport transform.
- [ ] Backface cull using screen-space signed area.
- [ ] Flat-shade each triangle with Lambert `N . L`, pick a palette index
      from a pre-baked ramp.
- [ ] For small meshes: sort back-to-front (painter's) and call `ttri`
      without z-values. For bigger / dynamic scenes: pass `z1, z2, z3` and
      let the depth buffer handle it.
- [ ] Sort translucent triangles back-to-front and draw after opaques.
- [ ] Call `ttri(..., z1, z2, z3)` with your projected vertices and let
      TIC-80 handle rasterization, perspective-correct UVs, and depth
      testing.
- [ ] `cls()` every frame — it also clears the depth buffer.
- [ ] Localize every global used in hot loops, pre-allocate vertex pools,
      and replace hashed fields with array indices.

