import haxe.io.Eof;
import haxe.io.Path;

#if sys
import sys.FileSystem;
import sys.io.Process;
#end

class Run
{
    static inline var LIB_NAME = "librl-hx";
    static inline var LIBRL_PATH = "project/lib/librl";

    static function main():Void
    {
        #if !sys
        Sys.println(LIB_NAME + " helper commands require a sys target.");
        Sys.exit(1);
        #else
        var args = Sys.args();
        if (args.length > 0 && looksLikeInjectedLibPath(args[0]))
        {
            args.shift();
        }
        var command = args.shift();

        switch (command)
        {
            case null, "help", "-h", "--help":
                printHelp();
            case "librl-status":
                runFromRepo(printStatus);
            case "librl-unpin":
                runFromRepo(syncLibrl);
            case "librl-pin":
                runFromRepo(function(root) {
                    return bumpSubmodule(root, args);
                });
            case "librl-reset":
                runFromRepo(resetLibrl);
            case _:
                Sys.println('Unknown command: ${command}');
                printHelp();
                Sys.exit(1);
        }
        #end
    }

    #if sys
    static function runFromRepo(action:String->Int):Void
    {
        var repoRoot = resolveRepoRoot();
        if (repoRoot == null)
        {
            Sys.println("Could not locate the librl-hx repository root.");
            Sys.exit(1);
        }

        var previousCwd = Sys.getCwd();
        Sys.setCwd(repoRoot);
        var exitCode = 0;
        try
        {
            exitCode = action(repoRoot);
        }
        catch (error:Dynamic)
        {
            Sys.setCwd(previousCwd);
            throw error;
        }

        Sys.setCwd(previousCwd);
        if (exitCode != 0) Sys.exit(exitCode);
    }

    static function printStatus(repoRoot:String):Int
    {
        Sys.println('librl-hx root: ${repoRoot}');
        Sys.println("");

        var exitCode = 0;
        exitCode = runStreaming("git", ["status", "--short", "-b"]);
        if (exitCode != 0) return exitCode;

        Sys.println("");
        exitCode = runStreaming("git", ["-C", LIBRL_PATH, "status", "--short", "-b"]);
        if (exitCode != 0) return exitCode;

        Sys.println("");
        return runStreaming("git", ["diff", "--submodule=log", "--", LIBRL_PATH]);
    }

    static function syncLibrl(repoRoot:String):Int
    {
        var dirty = capture("git", ["-C", LIBRL_PATH, "status", "--short"]);
        if (dirty.code != 0) return printCommandFailure(dirty);
        if (StringTools.trim(dirty.stdout) != "")
        {
            Sys.println("Refusing to sync because project/lib/librl has uncommitted changes.");
            Sys.println("Commit, stash, or discard them first.");
            return 1;
        }

        var steps = [
            ["-C", LIBRL_PATH, "fetch", "origin"],
            ["-C", LIBRL_PATH, "switch", "main"],
            ["-C", LIBRL_PATH, "pull", "--ff-only"]
        ];

        for (step in steps)
        {
            var exitCode = runStreaming("git", step);
            if (exitCode != 0) return exitCode;
        }

        return 0;
    }

    static function bumpSubmodule(repoRoot:String, args:Array<String>):Int
    {
        var diff = capture("git", ["diff", "--name-only", "--", LIBRL_PATH]);
        if (diff.code != 0) return printCommandFailure(diff);
        if (StringTools.trim(diff.stdout) == "")
        {
            Sys.println("No librl submodule pointer change to commit.");
            return 0;
        }

        var message = args.length > 0 ? args.join(" ") : "Update librl submodule";
        var addCode = runStreaming("git", ["add", LIBRL_PATH]);
        if (addCode != 0) return addCode;

        return runStreaming("git", ["commit", "-m", message]);
    }

    static function resetLibrl(repoRoot:String):Int
    {
        return runStreaming("git", ["submodule", "update", "--checkout", LIBRL_PATH]);
    }

    static function printHelp():Void
    {
        Sys.println("librl-hx helper commands:");
        Sys.println("  haxelib run librl-hx librl-status");
        Sys.println("  haxelib run librl-hx librl-unpin");
        Sys.println("  haxelib run librl-hx librl-pin [commit message]");
        Sys.println("  haxelib run librl-hx librl-reset");
        Sys.println("");
        Sys.println("librl-status  Show parent and submodule git status.");
        Sys.println("librl-unpin   Switch librl to main and pull --ff-only for live development.");
        Sys.println("librl-pin     Commit the parent repo's librl submodule pointer.");
        Sys.println("librl-reset   Reset librl back to the submodule commit pinned by librl-hx.");
    }

    static function resolveRepoRoot():Null<String>
    {
        var current = Path.normalize(Sys.getCwd());
        while (true)
        {
            if (isRepoRoot(current)) return current;
            var parent = Path.directory(current);
            if (parent == current) break;
            current = parent;
        }

        var haxelibPath = capture("haxelib", ["libpath", LIB_NAME]);
        if (haxelibPath.code != 0) return null;

        for (line in haxelibPath.stdout.split("\n"))
        {
            var candidate = StringTools.trim(line);
            if (candidate == "") continue;
            candidate = Path.normalize(candidate);
            if (isRepoRoot(candidate)) return candidate;
        }

        return null;
    }

    static function isRepoRoot(path:String):Bool
    {
        return FileSystem.exists(Path.join([path, "haxelib.json"]))
            && FileSystem.exists(Path.join([path, LIBRL_PATH]));
    }

    static function looksLikeInjectedLibPath(value:String):Bool
    {
        if (value == null || value == "") return false;
        if (!FileSystem.exists(value)) return false;
        return FileSystem.isDirectory(value) && isRepoRoot(Path.normalize(value));
    }

    static function runStreaming(command:String, args:Array<String>):Int
    {
        Sys.println('$command ${args.join(" ")}');
        return Sys.command(command, args);
    }

    static function capture(command:String, args:Array<String>):CommandResult
    {
        var process = new Process(command, args);
        var stdout = readStream(process.stdout);
        var stderr = readStream(process.stderr);
        var code = process.exitCode();
        process.close();
        return {
            code: code,
            stdout: stdout,
            stderr: stderr
        };
    }

    static function readStream(input:haxe.io.Input):String
    {
        try
        {
            return input.readAll().toString();
        }
        catch (_:Eof)
        {
            return "";
        }
    }

    static function printCommandFailure(result:CommandResult):Int
    {
        if (result.stdout != "") Sys.print(result.stdout);
        if (result.stderr != "") Sys.print(result.stderr);
        return result.code;
    }
    #end
}

#if sys
typedef CommandResult = {
    var code:Int;
    var stdout:String;
    var stderr:String;
}
#end
