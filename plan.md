# Dual Contouring / Marching Cubes App - Implementation Plan

## Context

TIC-Labs is an experimentation repo. This is a **standalone Three.js project** — not related to TIC-80. It lives in `games/dual-contour/` simply because that's where experiments go.

---

## Architecture Overview

**Single deliverable:** `games/dual-contour/index.html` — a self-contained HTML file with inline JS implementing marching cubes over a user-editable voxel grid.

**Tech choices:**
- Three.js (r160+) loaded from CDN via ES module import maps
- OrbitControls from Three.js addons CDN for camera
- Marching cubes algorithm implemented from scratch in JS (classic Paul Bourke lookup tables)
- No build step, no bundler, no dependencies beyond CDN

---

## Reference Projects & Code Snippets

### 1. Paul Bourke — The Canonical Marching Cubes Reference

Source: https://paulbourke.net/geometry/polygonise/

The foundational data structures and the `Polygonise` function that every MC implementation derives from:

```c
typedef struct {
   XYZ p[3];
} TRIANGLE;

typedef struct {
   XYZ p[8];
   double val[8];
} GRIDCELL;
```

**Vertex Interpolation** — finds where the isosurface crosses an edge:

```c
XYZ VertexInterp(double isolevel, XYZ p1, XYZ p2,
                 double valp1, double valp2)
{
   double mu;
   XYZ p;

   if (ABS(isolevel-valp1) < 0.00001)
      return(p1);
   if (ABS(isolevel-valp2) < 0.00001)
      return(p2);
   if (ABS(valp1-valp2) < 0.00001)
      return(p1);
   mu = (isolevel - valp1) / (valp2 - valp1);
   p.x = p1.x + mu * (p2.x - p1.x);
   p.y = p1.y + mu * (p2.y - p1.y);
   p.z = p1.z + mu * (p2.z - p1.z);

   return(p);
}
```

**Polygonise** — the core algorithm per cube cell:

```c
int Polygonise(GRIDCELL grid, double isolevel, TRIANGLE *triangles)
{
   int i, ntriang;
   int cubeindex;
   XYZ vertlist[12];

   // Determine the index into the edge table which
   // tells us which vertices are inside of the surface
   cubeindex = 0;
   if (grid.val[0] < isolevel) cubeindex |= 1;
   if (grid.val[1] < isolevel) cubeindex |= 2;
   if (grid.val[2] < isolevel) cubeindex |= 4;
   if (grid.val[3] < isolevel) cubeindex |= 8;
   if (grid.val[4] < isolevel) cubeindex |= 16;
   if (grid.val[5] < isolevel) cubeindex |= 32;
   if (grid.val[6] < isolevel) cubeindex |= 64;
   if (grid.val[7] < isolevel) cubeindex |= 128;

   // Cube is entirely in/out of the surface
   if (edgeTable[cubeindex] == 0)
      return(0);

   // Find the vertices where the surface intersects the cube
   if (edgeTable[cubeindex] & 1)
      vertlist[0] = VertexInterp(isolevel, grid.p[0], grid.p[1],
                                  grid.val[0], grid.val[1]);
   if (edgeTable[cubeindex] & 2)
      vertlist[1] = VertexInterp(isolevel, grid.p[1], grid.p[2],
                                  grid.val[1], grid.val[2]);
   if (edgeTable[cubeindex] & 4)
      vertlist[2] = VertexInterp(isolevel, grid.p[2], grid.p[3],
                                  grid.val[2], grid.val[3]);
   if (edgeTable[cubeindex] & 8)
      vertlist[3] = VertexInterp(isolevel, grid.p[3], grid.p[0],
                                  grid.val[3], grid.val[0]);
   if (edgeTable[cubeindex] & 16)
      vertlist[4] = VertexInterp(isolevel, grid.p[4], grid.p[5],
                                  grid.val[4], grid.val[5]);
   if (edgeTable[cubeindex] & 32)
      vertlist[5] = VertexInterp(isolevel, grid.p[5], grid.p[6],
                                  grid.val[5], grid.val[6]);
   if (edgeTable[cubeindex] & 64)
      vertlist[6] = VertexInterp(isolevel, grid.p[6], grid.p[7],
                                  grid.val[6], grid.val[7]);
   if (edgeTable[cubeindex] & 128)
      vertlist[7] = VertexInterp(isolevel, grid.p[7], grid.p[4],
                                  grid.val[7], grid.val[4]);
   if (edgeTable[cubeindex] & 256)
      vertlist[8] = VertexInterp(isolevel, grid.p[0], grid.p[4],
                                  grid.val[0], grid.val[4]);
   if (edgeTable[cubeindex] & 512)
      vertlist[9] = VertexInterp(isolevel, grid.p[1], grid.p[5],
                                  grid.val[1], grid.val[5]);
   if (edgeTable[cubeindex] & 1024)
      vertlist[10] = VertexInterp(isolevel, grid.p[2], grid.p[6],
                                   grid.val[2], grid.val[6]);
   if (edgeTable[cubeindex] & 2048)
      vertlist[11] = VertexInterp(isolevel, grid.p[3], grid.p[7],
                                   grid.val[3], grid.val[7]);

   // Create the triangles
   ntriang = 0;
   for (i = 0; triTable[cubeindex][i] != -1; i += 3) {
      triangles[ntriang].p[0] = vertlist[triTable[cubeindex][i]];
      triangles[ntriang].p[1] = vertlist[triTable[cubeindex][i+1]];
      triangles[ntriang].p[2] = vertlist[triTable[cubeindex][i+2]];
      ntriang++;
   }

   return(ntriang);
}
```

**Lookup tables** (first rows — full 256 entries embedded in final app):

```c
// edgeTable[256] — which edges are intersected for each cube config
int edgeTable[256] = {
  0x0  , 0x109, 0x203, 0x30a, 0x406, 0x50f, 0x605, 0x70c,
  0x80c, 0x905, 0xa0f, 0xb06, 0xc0a, 0xd03, 0xe09, 0xf00,
  0x190, 0x99 , 0x393, 0x29a, 0x596, 0x49f, 0x795, 0x69c,
  0x99c, 0x895, 0xb9f, 0xa96, 0xd9a, 0xc93, 0xf99, 0xe90,
  0x230, 0x339, 0x33 , 0x13a, 0x636, 0x73f, 0x435, 0x53c,
  // ... 256 total entries
};

// triTable[256][16] — triangle vertex indices per config, -1 terminated
int triTable[256][16] = {
  {-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
  {0, 8, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
  {0, 1, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
  {1, 8, 3, 9, 8, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
  {1, 2, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
  {0, 8, 3, 1, 2, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
  {9, 2, 10, 0, 2, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
  {2, 8, 3, 2, 10, 8, 10, 9, 8, -1, -1, -1, -1, -1, -1, -1},
  {3, 11, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
  {0, 11, 2, 8, 11, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
  // ... 256 total rows
};
```

---

### 2. KineticTactic/marching-cubes-js — Clean JS + Three.js Implementation

Source: https://github.com/KineticTactic/marching-cubes-js

A simple, readable JS implementation. Key patterns to adopt:

**Scalar field generation and marching loop** (`sketch.js`):

```javascript
// Noise-based scalar field on a 3D grid
let field = [];
let res = 0.5;
let xSize = 100, ySize = 100, zSize = 100;

// Fill the 3D field with noise values
let xoff = 0;
for (let i = 0; i < xSize; i++) {
    let yoff = 0;
    field[i] = [];
    for (let j = 0; j < ySize; j++) {
        let zoff = 0;
        field[i][j] = [];
        for (let k = 0; k < zSize; k++) {
            field[i][j][k] = noise.noise3D(xoff, yoff, zoff);
            zoff += increment;
        }
        yoff += increment;
    }
    xoff += increment;
}

// March through the field, process each cell
let vertices = [];
for (let i = 0; i < xSize - 1; i++) {
    let x = i * res;
    for (let j = 0; j < ySize - 1; j++) {
        let y = j * res;
        for (let k = 0; k < zSize - 1; k++) {
            let z = k * res;

            // Sample 8 corners of the cube
            let values = [
                field[i][j][k] + 1,
                field[i + 1][j][k] + 1,
                field[i + 1][j][k + 1] + 1,
                field[i][j][k + 1] + 1,
                field[i][j + 1][k] + 1,
                field[i + 1][j + 1][k] + 1,
                field[i + 1][j + 1][k + 1] + 1,
                field[i][j + 1][k + 1] + 1,
            ];

            // Interpolate edge intersection points
            let edges = [
                new THREE.Vector3(
                    lerp(x, x + res, (1 - values[0]) / (values[1] - values[0])),
                    y, z),
                new THREE.Vector3(
                    x + res, y,
                    lerp(z, z + res, (1 - values[1]) / (values[2] - values[1]))),
                new THREE.Vector3(
                    lerp(x, x + res, (1 - values[3]) / (values[2] - values[3])),
                    y, z + res),
                new THREE.Vector3(
                    x, y,
                    lerp(z, z + res, (1 - values[0]) / (values[3] - values[0]))),
                // ... edges 4-7 (top face), 8-11 (vertical edges)
            ];

            // Compute cube index from corner inside/outside states
            let state = getState(
                Math.ceil(field[i][j][k]),
                Math.ceil(field[i + 1][j][k]),
                // ... all 8 corners
            );

            // Look up triangles and emit vertices
            for (let edgeIndex of triangulationTable[state]) {
                if (edgeIndex !== -1) {
                    vertices.push(
                        edges[edgeIndex].x,
                        edges[edgeIndex].y,
                        edges[edgeIndex].z
                    );
                }
            }
        }
    }
}

// Build Three.js geometry
geometry = new THREE.BufferGeometry();
geometry.setAttribute("position",
    new THREE.BufferAttribute(new Float32Array(vertices), 3));
geometry.computeVertexNormals();
material = new THREE.MeshPhongMaterial({
    color: 0x0055ff, side: THREE.DoubleSide
});
mesh = new THREE.Mesh(geometry, material);
scene.add(mesh);
```

**Helper functions:**

```javascript
function lerp(start, end, amt) {
    return (1 - amt) * start + amt * end;
}

function getState(a, b, c, d, e, f, g, h) {
    return a * 1 + b * 2 + c * 4 + d * 8
         + e * 16 + f * 32 + g * 64 + h * 128;
}
```

---

### 3. Scrawk/Marching-Cubes — C# / Unity Base Architecture

Source: https://github.com/Scrawk/Marching-Cubes

Clean separation of the volume iteration loop from the per-cell march. Good architecture reference:

**Base class — volume iteration** (`Marching.cs`):

```csharp
public abstract class Marching
{
    public float Surface { get; set; }
    private float[] Cube { get; set; }
    protected int[] WindingOrder { get; private set; }

    public Marching(float surface)
    {
        Surface = surface;
        Cube = new float[8];
        WindingOrder = new int[] { 0, 1, 2 };
    }

    // Iterate through the 3D voxel volume
    public virtual void Generate(float[,,] voxels,
        IList<Vector3> verts, IList<int> indices)
    {
        int width = voxels.GetLength(0);
        int height = voxels.GetLength(1);
        int depth = voxels.GetLength(2);

        for (int x = 0; x < width - 1; x++) {
            for (int y = 0; y < height - 1; y++) {
                for (int z = 0; z < depth - 1; z++) {
                    // Get values at the 8 cube corners
                    for (int i = 0; i < 8; i++) {
                        int ix = x + VertexOffset[i, 0];
                        int iy = y + VertexOffset[i, 1];
                        int iz = z + VertexOffset[i, 2];
                        Cube[i] = voxels[ix, iy, iz];
                    }
                    March(x, y, z, Cube, verts, indices);
                }
            }
        }
    }

    // Interpolation: find where isosurface crosses an edge
    protected virtual float GetOffset(float v1, float v2)
    {
        float delta = v2 - v1;
        return (delta == 0.0f) ? Surface : (Surface - v1) / delta;
    }

    // Per-cell marching — subclass implements this
    protected abstract void March(float x, float y, float z,
        float[] cube, IList<Vector3> vertList, IList<int> indexList);

    // Cube corner positions relative to (0,0,0)
    protected static readonly int[,] VertexOffset = new int[,]
    {
        {0, 0, 0},{1, 0, 0},{1, 1, 0},{0, 1, 0},
        {0, 0, 1},{1, 0, 1},{1, 1, 1},{0, 1, 1}
    };
}
```

---

### 4. Three.js Official Marching Cubes Example

Source: https://github.com/mrdoob/three.js/blob/dev/examples/webgl_marchingcubes.html

Uses the built-in `MarchingCubes` addon class with metaballs. Key setup patterns:

```javascript
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { MarchingCubes } from 'three/addons/objects/MarchingCubes.js';

// Scene + camera
camera = new THREE.PerspectiveCamera(45,
    window.innerWidth / window.innerHeight, 1, 10000);
camera.position.set(-500, 500, 1500);
scene = new THREE.Scene();
scene.background = new THREE.Color(0x050505);

// Lights
light = new THREE.DirectionalLight(0xffffff, 3);
light.position.set(0.5, 0.5, 1);
scene.add(light);
ambientLight = new THREE.AmbientLight(0x323232, 3);
scene.add(ambientLight);

// Marching cubes object (resolution 28, scale 700)
resolution = 28;
effect = new MarchingCubes(resolution,
    materials[current_material], true, true, 100000);
effect.position.set(0, 0, 0);
effect.scale.set(700, 700, 700);
scene.add(effect);

// Add metaballs to the field each frame
function updateCubes(object, time, numblobs) {
    object.reset();
    const strength = 1.2 / ((Math.sqrt(numblobs) - 1) / 4 + 1);
    for (let i = 0; i < numblobs; i++) {
        const ballx = Math.sin(i + 1.26 * time * ...) * 0.27 + 0.5;
        const bally = Math.abs(Math.cos(i + 1.12 * time * ...)) * 0.77;
        const ballz = Math.cos(i + 1.32 * time * ...) * 0.27 + 0.5;
        object.addBall(ballx, bally, ballz, strength, 12);
    }
    object.update();
}

// Render loop
renderer = new THREE.WebGLRenderer();
renderer.setAnimationLoop(animate);
const controls = new OrbitControls(camera, renderer.domElement);
```

> **Note:** We will NOT use the built-in `MarchingCubes` class — it's designed for metaballs with `addBall()`. We need our own implementation that operates on a voxel grid. But the scene/camera/controls setup is reusable.

---

### 5. Three.js Voxel Painter — Interaction Model

Source: https://threejs.org/examples/webgl_interactive_voxelpainter.html

The click-to-add/remove UX we want. Key interaction patterns:

```javascript
// Raycasting setup
const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();

// On pointer move: find intersection, snap preview cube to grid
function onPointerMove(event) {
    pointer.set(
        (event.clientX / window.innerWidth) * 2 - 1,
        -(event.clientY / window.innerHeight) * 2 + 1
    );
    raycaster.setFromCamera(pointer, camera);
    const intersects = raycaster.intersectObjects(objects);
    if (intersects.length > 0) {
        const intersect = intersects[0];
        // Snap rollover mesh to the face normal direction
        rollOverMesh.position.copy(intersect.point)
            .add(intersect.face.normal);
        rollOverMesh.position
            .divideScalar(50).floor()
            .multiplyScalar(50).addScalar(25);
    }
}

// On click: add or remove voxel
function onPointerDown(event) {
    raycaster.setFromCamera(pointer, camera);
    const intersects = raycaster.intersectObjects(objects);
    if (intersects.length > 0) {
        const intersect = intersects[0];
        if (isShiftDown) {
            // REMOVE: delete the intersected cube
            if (intersect.object !== plane) {
                scene.remove(intersect.object);
                objects.splice(objects.indexOf(intersect.object), 1);
            }
        } else {
            // ADD: place new cube at face normal offset
            const voxel = new THREE.Mesh(cubeGeo, cubeMaterial);
            voxel.position.copy(intersect.point)
                .add(intersect.face.normal);
            voxel.position
                .divideScalar(50).floor()
                .multiplyScalar(50).addScalar(25);
            scene.add(voxel);
            objects.push(voxel);
        }
    }
}
```

> **Adaptation for our app:** Instead of adding individual cube meshes, clicks modify the voxel grid `Map`, then we regenerate the marching cubes mesh. The raycasting target is the MC mesh itself, and the face normal tells us which neighboring cell to fill.

---

### 6. Dwilliamson Lookup Tables Gist

Source: https://gist.github.com/dwilliamson/c041e3454a713e58baf6e4f8e5fffecd

Alternative table format mapping edges to vertex pairs:

```javascript
const EdgeVertexIndices = [
  [0, 1], [1, 3], [3, 2], [2, 0],
  [4, 5], [5, 7], [7, 6], [6, 4],
  [0, 4], [1, 5], [3, 7], [2, 6]
];
```

---

### 7. Roblox & Unity — Games Using Click-to-Edit MC Terrain

- **Javier-Garzo/Marching-cubes-on-Unity-3D** (https://github.com/Javier-Garzo/Marching-cubes-on-Unity-3D): Unity voxel engine, left-click add / right-click remove, Job System + Burst for chunk generation. Closest UX match.
- **Roblox MC Terrain** (https://devforum.roblox.com/t/marching-cubes-voxel-terrain-with-tools/602593): Same add/remove paradigm.
- **ivanwang123/marching-cubes-v2** (https://github.com/ivanwang123/marching-cubes-v2): Procedural 3D world with destructible terrain in JS + Three.js.

### 8. Algorithm Comparisons (0fps.net)

Source: https://0fps.net/2012/07/12/smooth-voxel-terrain-part-2/

Key insight: Marching Cubes produces smooth meshes but can't do sharp features. Dual Contouring uses hermite data (edge intersection normals) to preserve sharp edges. Surface Nets is a simpler dual method. For voxel editing with cubic volumes, MC is the right choice — the smoothing effect is desirable.

---

## Step-by-step Plan

### Step 1: Create `games/dual-contour/index.html` — The Marching Cubes App

Single self-contained HTML file with all JS inline.

#### 1a: HTML Shell & Styles
- Dark background (`#0f0f1a`)
- Full-viewport `<canvas>` for Three.js
- Minimal HUD overlay showing controls and voxel count
- Small toolbar for toggling wireframe, resetting grid

#### 1b: Three.js Scene Setup
- Import Three.js + OrbitControls from CDN via ES module import maps
- Scene, perspective camera, WebGL renderer
- Ambient + directional lighting
- OrbitControls (drag to rotate, scroll to zoom)
- Grid helper on ground plane

#### 1c: Voxel Grid Data Structure
- `VoxelGrid` class backed by a `Map` using string keys (`"x,y,z"`)
- Methods: `set(x,y,z)`, `remove(x,y,z)`, `has(x,y,z)`
- Start with a single voxel at origin `(0,0,0)`
- Each voxel is 1 unit cubed

#### 1d: Marching Cubes Implementation
- Full 256-entry edgeTable and triTable (Paul Bourke) embedded inline
- For each cell in the bounding box of the voxel grid (with 1-cell padding):
  - Sample 8 corners (1.0 if any adjacent voxel is filled, 0.0 otherwise)
  - Compute cubeindex from corner in/out states
  - Look up edges in edgeTable
  - Interpolate edge vertices via VertexInterp (isolevel 0.5)
  - Emit triangles from triTable
- Returns a Three.js `BufferGeometry` with positions and computed normals

#### 1e: Interaction — Adding/Removing Voxels
- Raycast against the MC mesh to find hit point + face normal
- From hit point + normal, determine which adjacent empty cell to fill
- Show translucent wireframe "ghost cube" as placement preview
- **Left-click**: Add voxel at ghost position, regenerate mesh
- **Right-click**: Remove the nearest voxel, regenerate mesh
- Context menu suppressed

#### 1f: Visual Polish
- `MeshStandardMaterial` with slight metallic/roughness
- Optional wireframe overlay
- Optional voxel grid wireframe outlines
- Ground grid for spatial reference

#### 1g: HUD & Controls
- Top-left: "Dual Contour - Marching Cubes Editor"
- Bottom bar: "LMB: Add | RMB: Remove | Scroll: Zoom | Drag: Orbit"
- Buttons: [Reset] [Toggle Wireframe] [Toggle Voxel Grid]

### Step 2: Commit & Push

- Commit with descriptive message
- Push to `claude/dual-contour-marching-cubes-uSUwh`

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `games/dual-contour/meta.json` | Already created | Metadata |
| `games/dual-contour/index.html` | Create | The marching cubes app |

---

## Key Technical Decisions

1. **Marching Cubes over Dual Contouring**: MC is simpler, produces the continuous mesh the user wants, and works well for axis-aligned voxels. True DC requires hermite data which adds complexity without clear benefit here.

2. **Scalar field approach**: Each filled voxel sets its 8 corner vertices to 1.0. Isolevel at 0.5 produces a smooth shell that bridges adjacent cubes into one continuous mesh.

3. **Own MC implementation (not Three.js addon)**: The built-in `MarchingCubes` class is designed for metaballs (`addBall()`). We need direct control over the scalar field from a voxel grid.

4. **Interaction model from voxel painter**: Raycast + face normal to determine placement cell, adapted from Three.js voxel painter example. But targeting the MC mesh surface instead of individual box meshes.
