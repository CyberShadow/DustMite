/// DustMite, a D test case minimization tool
/// Written by Vladimir Panteleev <vladimir@thecybershadow.net>
/// Released into the Public Domain

module dustmite;

import std.stdio;
import std.file;
import std.path;
import std.string;
import std.getopt;
import std.array;
import std.process;
import std.algorithm;
import std.exception;
import std.datetime;
import std.regex;
import dsplit;

alias std.string.join join;

string dir, tester;
Entity[] set;

struct Times { Duration load, testSave, resultSave, test, clean, misc; }
Times times;
SysTime lastTime;
Duration elapsedTime() { auto c = Clock.currTime(); auto d = c - lastTime; lastTime = c; return d; }
void measure(string what)(void delegate() p) { times.misc += elapsedTime(); p(); mixin("times."~what~" += elapsedTime();"); }

int main(string[] args)
{
	bool force, dump, showTimes;
	string[] noRemoveStr;

	getopt(args,
		"force", &force,
		"noremove", &noRemoveStr,
		"dump", &dump,
		"times", &showTimes,
	);

	if (args.length == 0 || args.length>3)
	{
		stderr.write(
"Usage: "~args[0]~" [OPTION]... DIR TESTER
DIR should be a clean copy containing the file-set to reduce.
TESTER should be a shell command which returns 0 for a correct reduction,
and anything else otherwise.
Supported options:
  --force            Force reduction of unusual files
  --noremove REGEXP  Do not reduce blocks containing REGEXP
                       (may be used multiple times)
  --dump             Dump parsed tree to DIR.dump file
  --times            Display verbose spent time breakdown
");
		return 64; // EX_USAGE
	}

	dir = chomp(args[1], sep);
	if (altsep.length) dir = chomp(args[1], altsep);
	if (args.length>=3)
		tester = args[2];

	if (!force)
		foreach (path; listdir(dir, "*"))
			if (basename(path).startsWith(".") || basename(dirname(path)).startsWith(".") || getExt(path)=="o" || getExt(path)=="obj" || getExt(path)=="exe")
			{
				stderr.writefln("Suspicious file found: %s\nYou should use a clean copy of the source tree.\nIf it was your intention to include this file in the file-set to be reduced,\nre-run dustmite with the --force option.", path);
				return 1;
			}

	string resultDir = dir ~ ".reduced";
	enforce(!exists(resultDir), "Result directory already exists");

	auto startTime = lastTime = Clock.currTime();

	measure!"load"({set = loadFiles(dir);});
	applyNoRemove(noRemoveStr);

	if (dump)
		dumpSet(dir ~ ".dump");

	if (tester is null)
	{
		writeln("No tester specified, exiting");
		return 0;
	}

	if (!test(null))
		throw new Exception("Initial test fails");

	bool tested;
	int iterCount;
	do
	{
		writefln("############### ITERATION %d ################", iterCount++);
		bool changed;
		int testLevel = 0;
		do
		{
			writefln("============= Level %d =============", testLevel);
			tested = changed = false;

			enum MAX_DEPTH = 1024;
			int[MAX_DEPTH] address;

			void scan(ref Entity[] entities, int level)
			{
				int i = 0;
				while (i<entities.length)
				{
					address[level] = i;
					if (level < testLevel)
					{
						// recurse
						scan(entities[i].children, level+1);
						i++;
					}
					else
					if (entities[i].noRemove)
					{
						// skip, but don't stop going deeper
						tested = true;
						i++; 
					}
					else
					{
						// test
						tested = true;
						if (test(address[0..level+1]))
						{
							entities = remove(entities, i);
							measure!"resultSave"({safeSave(null, resultDir);});
							changed = true;
						}
						else
							i++;
					}
				}
			}

			scan(set, 0);
			//writefln("Scan results: tested=%s, changed=%s", tested, changed);

			testLevel++;
		} while (tested && !changed); // go deeper while we found something to test, but no results
	} while (tested); // stop when we didn't find anything to test

	auto duration = Clock.currTime()-startTime;
	duration = dur!"msecs"(duration.total!"msecs"); // truncate anything below ms, users aren't interested in that
	writefln("Done in %s; reduced version is in %s", duration, resultDir);

	if (showTimes)
		foreach (i, t; times.tupleof)
			writefln("%s: %s", times.tupleof[i].stringof, times.tupleof[i]);

	return 0;
}

void save(int[] address, string savedir)
{
	enforce(!exists(savedir), "Directory already exists: " ~ savedir);
	mkdirRecurse(savedir);

	foreach (i, f; set)
	{
		if (address.length==1 && address[0]==i) // skip this file
			continue;

		auto path = std.path.join(savedir, f.filename);
		if (!exists(dirname(path)))
			mkdirRecurse(dirname(path));
		auto o = File(path, "wb");

		void dump(Entity[] entities, int[] address)
		{
			foreach (i, e; entities)
			{
				if (address.length==1 && address[0]==i) // skip this entity
					continue;

				o.write(e.head);
				dump(e.children, address.length>1 && address[0]==i ? address[1..$] : null);
				o.write(e.tail);
			}
		}

		dump(f.children, address.length>1 && address[0]==i ? address[1..$] : null);
		o.close();
	}
}

void safeSave(int[] address, string savedir)
{
	auto tempdir = savedir ~ ".inprogress"; scope(failure) rmdirRecurse(tempdir);
	if (exists(tempdir)) rmdirRecurse(tempdir);
	save(null, tempdir);
	if (exists(savedir)) rmdirRecurse(savedir);
	rename(tempdir, savedir);
}

string formatAddress(int[] address)
{
	string[] segments = new string[address.length];
	Entity[] e = set;
	foreach (i, a; address)
	{
		segments[i] = format("%d/%d", a+1, e.length);
		e = e[a].children;
	}
	return "[" ~ segments.join(", ") ~ "]";
}

bool test(int[] address)
{
	string testdir = dir ~ ".test";
	measure!"testSave"({save(address, testdir);}); scope(exit) measure!"clean"({rmdirRecurse(testdir);});

	auto lastdir = getcwd(); scope(exit) chdir(lastdir);
	chdir(testdir);

	write("Test ", formatAddress(address), " => "); stdout.flush();

	bool result;
	measure!"test"({result = system(tester) == 0;});
	writeln(result);
	return result;
}

void applyNoRemove(string[] noRemoveStr)
{
	auto noRemove = map!regex(noRemoveStr);

	void mark(Entity[] set)
	{
		foreach (ref e; set)
		{
			e.noRemove = true;
			mark(e.children);
		}
	}

	bool scan(Entity[] set)
	{
		bool found = false;
		foreach (ref e; set)
			if (canFind!((a){return !match(e.head, a).empty || !match(e.tail, a).empty;})(noRemove))
			{
				e.noRemove = true;
				mark(e.children);
				found = true;
			}
			else
			if (scan(e.children))
			{
				e.noRemove = true;
				found = true;
			}
		return found;
	}

	scan(set);
}

void dumpSet(string fn)
{
	auto f = File(fn, "wt");

	string printable(string s)
	{
		return s is null ? "null" : `"` ~ s.replace("\\", `\\`).replace("\"", `\"`).replace("\r", `\r`).replace("\n", `\n`) ~ `"`;
	}

	void print(Entity[] entities, int level)
	{
		auto prefix = replicate("  ", level);
		foreach (e; entities)
		{
			if (e.children.length == 0)
			{
				f.writeln(prefix, "[ ", e.head ? printable(e.head) ~ " " : null, e.tail ? printable(e.tail) ~ " " : null, "]");
			}
			else
			{
				f.writeln(prefix, "[", e.isPair ? " // Pair" : null);
				if (e.head) f.writeln(prefix, "  ", printable(e.head));
				print(e.children, level+1);
				if (e.tail) f.writeln(prefix, "  ", printable(e.tail));
				f.writeln(prefix, "]");
			}
		}
	}

	foreach (e; set)
	{
		f.writefln("/*** %s ***/", e.filename);
		print(e.children, 0);
	}
	f.close();
}
