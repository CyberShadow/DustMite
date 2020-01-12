import std.algorithm;
import std.array;
import std.exception;
import std.file;
import std.getopt;
import std.parallelism;
import std.path;
import std.process;
import std.stdio;
import std.string;

/// Obviously different compiler versions will compile D programs differently.
/// Thus, we should use a specific version to run the Dustmite test suite against,
/// so we can distinguish changes in results due to Dustmite bugs or unexpected effects of changes,
/// from changes due to differences in how D compiler versions compile D programs.
// Note: when updating this, also update README.md.
enum testSuiteDMDVersion = "v2.080.0";

void main(string[] args)
{
	string[] exclude;
	getopt(args,
		"exclude", &exclude,
	);

	auto tests = args[1..$];
	if (tests.empty)
	{
		tests = dirEntries(".", SpanMode.shallow)
			.filter!(de => de.isDir)
			.map!(de => de.name)
			.filter!(name => !exclude.canFind(name))
			.array;
	}

	{
		auto result = execute(["dmd", "--version"]);
		enforce(result.status == 0, "Can't execute dmd compiler");
		auto dmdVersion = result.output.splitLines[0].split[$-1];
		if (dmdVersion != testSuiteDMDVersion)
			stderr.writefln("WARNING: dmd binary in PATH is version %s, not %s.\n  Test results may be wrong.",
				dmdVersion, testSuiteDMDVersion);
	}

	auto dustmite = buildPath("..", "dustmite");
	immutable flags = ["-g", "-debug"];
	stderr.writeln("Building...");
	{
		auto status = spawnProcess(["rdmd", "--build-only"] ~ flags ~ [dustmite]).wait();
		enforce(status == 0, "Dustmite build failed with status %s".format(status));
	}

	auto mutex = new Object;

	foreach (test; tests.parallel)
	{
		scope(failure) stderr.writefln("runtests: Error with test %s", test);

		auto target = test~"/src";
		if (!target.exists)
			target = test~"/src.d";
		version (Windows)
			enum testFile = "test.cmd";
		else
			enum testFile = "test.sh";
		auto tester = test~"/" ~ testFile;
		auto testerCmd = ".." ~ dirSeparator ~ testFile;

		auto tempDir = target.setExtension("temp");
		if (tempDir.exists) tempDir.rmdirRecurse();
		auto reducedDir = target.setExtension("reduced");
		if (reducedDir.exists) reducedDir.rmdirRecurse();
		auto resultDir = target.setExtension("result");
		if (resultDir.exists) resultDir.rmdirRecurse();

		string[] opts;
		auto optsFile = test~"/opts.txt";
		if (optsFile.exists)
			opts = optsFile.readText().splitLines();

		auto outputFile = test~"/output.txt";
		File output;
		synchronized(mutex) output.open(outputFile, "wb");

		stderr.writefln("runtests: test %s: dumping", test);
		auto status = spawnProcess(["rdmd"] ~ flags ~ [dustmite] ~ opts ~ ["--dump", "--no-optimize", target],
			stdin, output, output, null, Config.retainStdout | Config.retainStderr).wait();
		enforce(status == 0, "Dustmite dump failed with status %s".format(status));
		stderr.writefln("runtests: test %s: done", test);

		if (!tester.exists)
			continue; // dump only

		synchronized(mutex) output.reopen(outputFile, "ab"); // Reopen because spawnProcess closes it
		stderr.writefln("runtests: test %s: reducing", test);
		status = spawnProcess(["rdmd"] ~ flags ~ [dustmite] ~ opts ~ ["--times", target, testerCmd],
			stdin, output, output, null, Config.retainStdout | Config.retainStderr).wait();
		enforce(status == 0, "Dustmite run failed with status %s".format(status));
		stderr.writefln("runtests: test %s: done", test);

		rename(reducedDir, resultDir);
		synchronized(mutex) output.close();
		auto progress = File(test~"/progress.txt", "wb");
		foreach (line; File(outputFile, "rb").byLine())
		{
			line = line.strip();
			if (line.startsWith("[") || line.startsWith("#") || line.startsWith("=") || line.startsWith("ReplaceWord"))
				progress.writeln(line);
			else
			if (line.startsWith("Done in "))
				progress.writeln(line.split()[0..4].join(" "));
		}
	}
}
