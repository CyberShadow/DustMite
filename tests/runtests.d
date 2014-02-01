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
		auto resultDir = target.setExtension("result");
		if (resultDir.exists) resultDir.rmdirRecurse();

		string[] opts;
		auto optsFile = test~"/opts.txt";
		if (optsFile.exists)
			opts = optsFile.readText().splitLines();

		auto dustmite = buildPath("..", "dustmite");
		auto outputFile = test~"/output.txt";
		auto output = File(outputFile, "wb");

		stderr.writefln("runtests: test %s: dumping", test);
		auto status = spawnProcess([dustmite] ~ opts ~ ["--dump", "--no-optimize", target], stdin, output, output).wait();
		enforce(status == 0, "Dustmite dump failed with status %s".format(status));
		stderr.writefln("runtests: test %s: done", test);

		output = File(outputFile, "ab"); // Reopen because spawnProcess closes it
		stderr.writefln("runtests: test %s: reducing", test);
		status = spawnProcess([dustmite] ~ opts ~ ["--times", target, tester], stdin, output, output).wait();
		enforce(status == 0, "Dustmite run failed with status %s".format(status));
		stderr.writefln("runtests: test %s: done", test);

		rename(reducedDir, resultDir);
		output.close();
		auto progress = File(test~"/progress.txt", "wb");
		foreach (line; File(outputFile, "rb").byLine())
		{
			line = line.strip();
			if (line.startsWith("[") || line.startsWith("#") || line.startsWith("ReplaceWord"))
				progress.writeln(line);
			else
			if (line.startsWith("Done in "))
				progress.writeln(line.split()[0..4].join(" "));
		}
	}
}
