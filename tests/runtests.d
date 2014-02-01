import std.algorithm;
import std.array;
import std.exception;
import std.file;
import std.parallelism;
import std.path;
import std.process;
import std.stdio;
import std.string;

void main(string[] args)
{
	auto tests = args[1..$];
	if (tests.empty)
		tests = dirEntries("", SpanMode.shallow).filter!(de => de.isDir).map!(de => de.name).array;
	foreach (test; tests.parallel)
	{
		auto target = test~"/src";
		auto tester = ".." ~ dirSeparator ~ "test.cmd";
		if (!target.exists)
			target = test~"/src.d";

		auto tempDir = target.setExtension("temp");
		if (tempDir.exists) tempDir.rmdirRecurse();
		auto reducedDir = target.setExtension("reduced");
		if (reducedDir.exists) reducedDir.rmdirRecurse();

		auto dustmite = buildPath("..", "dustmite");
		auto output = File(test~"/output.txt", "wb");

		stderr.writefln("runtests: test %s: dumping", test);
		auto status = spawnProcess([dustmite, "--dump", "--no-optimize", target], stdin, output, output).wait();
		enforce(status == 0, "Dustmite dump failed with status %s".format(status));
		stderr.writefln("runtests: test %s: done", test);

		string[] testArgs;
		auto argsFile = test~"/args.txt";
		if (argsFile.exists)
			testArgs = argsFile.readText().splitLines();

		output = File(test~"/output.txt", "ab"); // Reopen because spawnProcess closes it
		stderr.writefln("runtests: test %s: reducing", test);
		status = spawnProcess([dustmite] ~ testArgs ~ ["--times", target, tester], stdin, output, output).wait();
		enforce(status == 0, "Dustmite run failed with status %s".format(status));
		stderr.writefln("runtests: test %s: done", test);
	}
}
