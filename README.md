# librl-hx

Haxe haxelib for [librl](https://github.com/robknopf/librl). Vendors the librl repo as a submodule, exposes its Haxe bindings on the classpath, and compiles native code (librl, wgutils, raylib) through hxcpp when you build your project.

Binding coverage follows the C headers on an as-needed basis. API reference lives in the librl repo: `docs/API.md`. Haxe-specific notes: `docs/BINDINGS.md` (in the submodule).

## Requirements

- Haxe **4.3+**
- **hxcpp** (desktop and wasm)
- **hxasync** (`@async` / `@await` on wasm and JS backends)
- **Neko** (hxcpp build tooling)
- **gcc/clang** (desktop)
- **Emscripten (`emcc`)** (wasm)

## Install

```bash
haxelib git librl-hx https://github.com/robknopf/librl-hx.git --recursive
```

`--recursive` pulls the librl, wgutils, and raylib submodules.

Local development:

```bash
git clone --recursive https://github.com/robknopf/librl-hx.git
haxelib dev librl-hx /path/to/librl-hx
```

Submodule maintenance helpers:

```bash
haxelib run librl-hx librl-status
haxelib run librl-hx librl-unpin
haxelib run librl-hx librl-pin "Update librl submodule"
haxelib run librl-hx librl-reset
```

`librl-unpin` is the safe prep step before editing `project/lib/librl`: it fetches `origin`, switches the submodule to `main`, and pulls with `--ff-only` so you do not commit on detached `HEAD`. After pushing `librl/main`, use `librl-pin` to commit the parent repo's updated submodule pointer. Use `librl-reset` to go back to the commit currently pinned by `librl-hx`.

Typical `librl` development flow from inside `librl-hx`:

```bash
# Optional: inspect parent + submodule state
haxelib run librl-hx librl-status

# Enter live librl development mode
haxelib run librl-hx librl-unpin

# Edit project/lib/librl/...
git -C project/lib/librl add ...
git -C project/lib/librl commit -m "..."
git -C project/lib/librl push origin main

# Pin librl-hx to that new librl commit
haxelib run librl-hx librl-pin "Update librl submodule"
git push
```

State model:

- `librl-unpin`: use live `librl/main` for development
- `librl-pin`: record the current `librl` commit in `librl-hx`
- `librl-reset`: restore `project/lib/librl` to the commit currently pinned by `librl-hx`

## Usage

```hxml
-lib librl-hx
-lib hxasync
```

No manual classpath or `LIBRL_ROOT`. `-lib librl-hx` sets the `librl_hx` define; stock `rl.InjectLibRL` includes `project/Build.xml` automatically.

**Desktop (hxcpp)** is the primary path: direct C FFI via `RLImpl.cpp.hx`.

**Wasm** uses hxcpp + Emscripten with the same bindings.

**JS target** (`RLImpl.js.hx`) adapts the librl JS binding and needs a JSPI-capable runtime. Treat as experimental.

On wasm/JS, call `RL.boot()` before `RL.init()`. On desktop, `boot()` exists but many apps can start with `init()` directly.

## API shape

| Layer | Role |
|-------|------|
| `rl.RL` | `boot`, `init`, `initAsync`, `deinit`, `tick`, version, timing |
| `rl.Fs`, `rl.Asset`, `rl.Window`, `rl.Render`, `rl.Input`, … | Subsystems mirroring `rl_*.h` |
| `rl.helpers.*` | Ergonomics (`TaskGroup`, `Wait`, `Log`) — not part of the C API |

Resources are integer handles (`RLHandle`). Create/use/destroy through section classes (`Texture.create`, `Model.draw`, …).

Init config (all fields optional):

```haxe
typedef RLInitConfig = {
    ?windowWidth:Int,
    ?windowHeight:Int,
    ?windowTitle:String,
    ?windowFlags:Int,
    ?assetHost:String,
    ?fsRootDir:String,
};
```

## Example snippets

Adapted from [`examples/haxe-simple`](https://github.com/robknopf/librl/blob/main/examples/haxe-simple/src/Main.hx) in the librl repo — same API calls, written for a normal `-lib librl-hx` project.

**Boot before init (wasm / JS):**

```haxe
import rl.RL;
import rl.helpers.Log;

@async
static function boot():Bool {
    var rc = @await RL.boot({ canvasId: "renderCanvas" });
    if (rc != RL.BOOT_OK) {
        Log.error("RL.boot failed: " + rc);
        return false;
    }
    return true;
}
```

**Init:**

```haxe
import rl.RL;
import rl.Window;
import rl.Logger;

@async
static function init():Bool {
    Logger.setLevel(Logger.LEVEL_WARN);
    var err = @await RL.init({
        windowWidth: 1024,
        windowHeight: 1280,
        windowTitle: "My Game",
        windowFlags: Window.FLAG_MSAA_4X_HINT,
        assetHost: "./",
    });
    if (err != RL.INIT_OK) return false;
    Logger.setLevel(Logger.LEVEL_INFO);
    return true;
}
```

**Frame loop:**

```haxe
import rl.RL;
import rl.Render;
import rl.Window;
import rl.Input;
import rl.Color;

static function frame(deltaTimeSec:Float):Bool {
    var rc = RL.tick();
    if (rc == RL.TICK_FAILED) return false;
    if (rc == RL.TICK_WAITING) return true;
    if (Window.closeRequested()) return false;

    var mouse = Input.getMouseState();

    Render.begin();
    Render.clearBackground(Color.RAYWHITE);
    // … draw …
    Render.end();

    return true;
}
```

**Async asset load:**

```haxe
import rl.Asset;
import rl.Model;
import rl.Texture;
import rl.Sprite3d;

// `userData` is an optional callback context (pass null if unused).
Asset.addTask(Asset.ensureAsync("assets/models/gumshoe/gumshoe.glb"), (path, _) -> {
    var model = Model.create(0);
    Model.setAsset(model, Model.loadAsset(path));
}, null, userData);

Asset.addTask(Asset.ensureAsync("assets/sprites/logo/wg-logo-bw-alpha.png"), (path, _) -> {
    var sprite = Sprite3d.create(0);
    Sprite3d.setTexture(sprite, Texture.create(path));
}, null, userData);
```

For a fuller scene (3D model, sprites, fonts, music, picking), see `Main.hx` in the librl `haxe-simple` example.

## Layout

```
librl-hx/
├── project/
│   ├── Build.xml                 # hxcpp native build (included when librl_hx is defined)
│   └── lib/
│       ├── librl/                # submodule → bindings/haxe/rl/*.hx
│       ├── wgutils/              # submodule
│       ├── raylib/               # submodule
│       ├── raylib.xml
│       └── wgutils.xml
├── test/
├── haxelib.json
└── README.md
```

## How it works

- `classPath` → `project/lib/librl/bindings/haxe` (submodule bindings).
- Stock `rl.InjectLibRL` in the submodule: `<include …/project/Build.xml if="librl_hx" />`, with the `LIBRL_ROOT` prebuilt path in `<section unless="librl_hx">`.
- `Build.xml` lists librl C sources and pulls in wgutils/raylib via included XML; hxcpp compiles everything into your app — no pre-built `.a` files.
- Desktop links system libs (X11, curl, OpenGL, etc.). Wasm sets Emscripten flags (GLFW, Fetch, IDBFS, JSPI, …).

## Test

```bash
cd test
haxe test_bindings.hxml
```

## License

MIT — see the librl repository for details.
