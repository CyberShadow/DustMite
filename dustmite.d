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
import dsplit;

string dir, tester;
Entity[] set;

void main(string[] args)
{
	getopt(args);
	if (args.length != 3)
		return writefln("Usage: %s DIR TESTER", args[0]);

	dir = chomp(args[1], sep);
	if (altsep.length) dir = chomp(args[1], altsep);
	tester = args[2];

	set = loadFiles(dir);

	//return dumpSet();

	if (!test(null))
		throw new Exception("Initial test fails");

	string resultDir = dir ~ ".reduced";
	enforce(!exists(resultDir), "Result directory already exists");

	bool tested;
	do
	{
		writeln("############### NEW ITERATION ################");
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
					if (level < testLevel) // recurse
					{
						scan(entities[i].children, level+1);
						i++;
					}
					else // test
					{
						tested = true;
						if (test(address[0..level+1]))
						{
							entities = remove(entities, i);
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

	save(null, resultDir);
	writeln("Done; saved to " ~ resultDir);
}

void save(int[] address, string savedir)
{
	foreach (i, f; set)
	{
		if (address.length==1 && address[0]==i) // skip this file
			continue;

		alias const(ubyte)[] Bytes;
		auto buf = appender!Bytes();

		void dump(Entity[] entities, int[] address)
		{
			foreach (i, e; entities)
			{
				if (address.length==1 && address[0]==i) // skip this entity
					continue;

				buf.put(cast(Bytes)e.header);
				dump(e.children, address.length>1 && address[0]==i ? address[1..$] : null);
				buf.put(cast(Bytes)e.footer);
			}
		}

		dump(f.children, address.length>1 && address[0]==i ? address[1..$] : null);

		auto path = std.path.join(savedir, f.filename);
		if (!exists(dirname(path)))
			mkdirRecurse(dirname(path));
		std.file.write(path, buf.data);
	}
}

bool test(int[] address)
{
	string testdir = dir ~ ".test";
	enforce(!exists(testdir), "Testing directory already exists");
	mkdir(testdir); scope(exit) rmdirRecurse(testdir);
	save(address, testdir);

	auto lastdir = getcwd(); scope(exit) chdir(lastdir);
	chdir(testdir);

	auto result = system(tester) == 0;
	writeln("Test ", address, " => ", result);
	return result;
}

void dumpSet()
{
	string printable(string s)
	{
		return s is null ? "null" : `"` ~ s.replace("\r", `\r`).replace("\n", `\n`) ~ `"`;
	}

	void print(Entity[] entities, int level)
	{
		foreach (e; entities)
		{
			if (e.isPair)
			{
				assert(e.children.length==2 && e.header is null && e.footer is null);
				writeln(format(replicate(">", level), " Pair"));
			}
			else
				writeln(format(replicate(">", level), " ", [printable(e.header), format(e.children.length), printable(e.footer)]));
			print(e.children, level+1);
		}
	}

	foreach (f; set)
	{
		writefln("=== %s ===", f.filename);
		print(f.children, 1);
	}
}
