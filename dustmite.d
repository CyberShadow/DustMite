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
import std.conv;
import std.md5;
import dsplit;

alias std.string.join join;

string dir, tester;
Entity[] set;

struct Times { Duration load, testSave, resultSave, test, clean, cacheHash, misc; }
Times times;
SysTime lastTime;
Duration elapsedTime() { auto c = Clock.currTime(); auto d = c - lastTime; lastTime = c; return d; }
void measure(string what)(void delegate() p) { times.misc += elapsedTime(); p(); mixin("times."~what~" += elapsedTime();"); }

struct Reduction
{
	enum Type { None, Remove, Unwrap }
	Type type;
	uint[] address;
}

int main(string[] args)
{
	bool force, dump, showTimes, stripComments;
	string coverageDir;
	string[] noRemoveStr;

	getopt(args,
		"force", &force,
		"noremove", &noRemoveStr,
		"strip-comments", &stripComments,
		"coverage", &coverageDir,
		"dump", &dump,
		"times", &showTimes,
	);

	if (args.length == 1 || args.length>3)
	{
		stderr.write(
"Usage: "~args[0]~" [OPTION]... PATH TESTER
PATH should be a directory containing a clean copy of the file-set to reduce.
A file path can also be specified. NAME.EXT will be treated like NAME/NAME.EXT.
TESTER should be a shell command which returns 0 for a correct reduction,
and anything else otherwise.
Supported options:
  --force            Force reduction of unusual files
  --noremove REGEXP  Do not reduce blocks containing REGEXP
                       (may be used multiple times)
  --strip-comments   Attempt to remove comments from source code.
  --coverage DIR     Load .lst files corresponding to source files from DIR
  --dump             Dump parsed tree to DIR.dump file
  --times            Display verbose spent time breakdown
");
		return 64; // EX_USAGE
	}

	enforce(!(stripComments && coverageDir), "Sorry, --strip-comments is not compatible with --coverage");

	dir = chomp(args[1], sep);
	if (altsep.length) dir = chomp(args[1], altsep);
	if (args.length>=3)
		tester = args[2];

	if (!force && isdir(dir))
		foreach (path; listdir(dir, "*"))
			if (basename(path).startsWith(".") || basename(dirname(path)).startsWith(".") || getExt(path)=="o" || getExt(path)=="obj" || getExt(path)=="exe")
			{
				stderr.writefln("Suspicious file found: %s\nYou should use a clean copy of the source tree.\nIf it was your intention to include this file in the file-set to be reduced,\nre-run dustmite with the --force option.", path);
				return 1;
			}

	auto startTime = lastTime = Clock.currTime();

	measure!"load"({set = loadFiles(dir, stripComments);});
	enforce(set.length, "No files in specified directory");

	string resultDir = dir ~ ".reduced";
	enforce(!exists(resultDir), "Result directory already exists");

	applyNoRemoveMagic();
	applyNoRemoveRegex(noRemoveStr);
	if (coverageDir)
		loadCoverage(coverageDir);

	if (dump)
		dumpSet(dir ~ ".dump");

	if (tester is null)
	{
		writeln("No tester specified, exiting");
		return 0;
	}

	if (!test(Reduction(Reduction.Type.None)))
		throw new Exception("Initial test fails");

	bool tested, foundAnything;
	int iterCount;
	do
	{
		writefln("############### ITERATION %d ################", iterCount++);
		bool changed;
		int testDepth = 0;
		do
		{
			writefln("============= Depth %d =============", testDepth);
			tested = changed = false;

			enum MAX_DEPTH = 1024;
			uint[MAX_DEPTH] address;

			void scan(ref Entity[] entities, int depth)
			{
				uint i = 0;
				while (i<entities.length)
				{
					address[depth] = i;
					if (depth < testDepth)
					{
						// recurse
						scan(entities[i].children, depth+1);
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
						if (test(Reduction(Reduction.Type.Remove, address[0..depth+1])))
						{
							entities = remove(entities, i);
							measure!"resultSave"({safeSave(null, resultDir);});
							foundAnything = changed = true;
						}
						else
						if (entities[i].head.length && entities[i].tail.length && test(Reduction(Reduction.Type.Unwrap, address[0..depth+1])))
						{
							entities[i].head = entities[i].tail = null;
							measure!"resultSave"({safeSave(null, resultDir);});
							foundAnything = changed = true;
						}
						else
							i++;
					}
				}
			}

			scan(set, 0);
			//writefln("Scan results: tested=%s, changed=%s", tested, changed);

			testDepth++;
		} while (tested && !changed); // go deeper while we found something to test, but no results
	} while (tested); // stop when we didn't find anything to test

	auto duration = Clock.currTime()-startTime;
	duration = dur!"msecs"(duration.total!"msecs"); // truncate anything below ms, users aren't interested in that
	if (foundAnything)
		writefln("Done in %s; reduced version is in %s", duration, resultDir);
	else
		writefln("Done in %s; no reductions found", duration);

	if (showTimes)
		foreach (i, t; times.tupleof)
			writefln("%s: %s", times.tupleof[i].stringof, times.tupleof[i]);

	return 0;
}

void dump(Entity[] entities, uint[] address, Reduction.Type reductionType, void delegate(string) writer)
{
	foreach (i, e; entities)
	{
		if (address.length==1 && address[0]==i)
		{
			final switch(reductionType)
			{
			case Reduction.Type.None:
				assert(0);
			case Reduction.Type.Remove: // skip this entity
				continue;
			case Reduction.Type.Unwrap: // skip head/tail
				dump(e.children, null, Reduction.Type.None, writer);
				break;
			}
		}
		else
		{
			if (e.head.length) writer(e.head);
			dump(e.children, address.length>1 && address[0]==i ? address[1..$] : null, reductionType, writer);
			if (e.tail.length) writer(e.tail);
		}
	}
}

void save(Reduction reduction, string savedir)
{
	enforce(!exists(savedir), "Directory already exists: " ~ savedir);
	mkdirRecurse(savedir);

	foreach (i, f; set)
	{
		if (reduction.address.length==1 && reduction.address[0]==i) // skip this file
		{
			assert(reduction.type == Reduction.Type.Remove);
			continue;
		}

		auto path = std.path.join(savedir, f.filename);
		if (!exists(dirname(path)))
			mkdirRecurse(dirname(path));

		auto o = File(path, "wb");
		dump(f.children, reduction.address.length>1 && reduction.address[0]==i ? reduction.address[1..$] : null, reduction.type, &o.write!string);
		o.close();
	}
}

void safeSave(int[] address, string savedir)
{
	auto tempdir = savedir ~ ".inprogress"; scope(failure) rmdirRecurse(tempdir);
	if (exists(tempdir)) rmdirRecurse(tempdir);
	save(Reduction(Reduction.Type.None), tempdir);
	if (exists(savedir)) rmdirRecurse(savedir);
	rename(tempdir, savedir);
}

string formatAddress(uint[] address)
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

bool[ubyte[16]] cache;

bool test(Reduction reduction)
{
	write(to!string(reduction.type), " ", formatAddress(reduction.address), " => "); stdout.flush();

	ubyte[16] digest;
	measure!"cacheHash"({
		MD5_CTX context;
		context.start();
		dump(set, reduction.address, reduction.type, cast(void delegate(string))&context.update);
		context.finish(digest);
	});
	auto cacheResult = digest in cache;
	if (cacheResult)
	{
		// Note: as far as I can see, a cache hit for a positive reduction is not possible (except, perhaps, for a no-op reduction)
		writeln(*cacheResult ? "Yes" : "No", " (cached)");
		return *cacheResult;
	}

	string testdir = dir ~ ".test";
	measure!"testSave"({save(reduction, testdir);}); scope(exit) measure!"clean"({rmdirRecurse(testdir);});

	auto lastdir = getcwd(); scope(exit) chdir(lastdir);
	chdir(testdir);

	bool result;
	measure!"test"({result = system(tester) == 0;});
	writeln(result ? "Yes" : "No");
	cache[digest] = result;
	return result;
}

void applyNoRemoveMagic()
{
	enum MAGIC_START = "DustMiteNoRemoveStart";
	enum MAGIC_STOP  = "DustMiteNoRemoveStop";

	bool state = false;

	bool scanString(string s)
	{
		if (s.length == 0)
			return false;
		if (s.canFind(MAGIC_START))
			state = true;
		if (s.canFind(MAGIC_STOP))
			state = false;
		return state;
	}

	bool scan(Entity[] set)
	{
		bool result = false;
		foreach (ref e; set)
		{
			bool removeThis;
			removeThis  = scanString(e.head);
			removeThis |= scan(e.children);
			removeThis |= scanString(e.tail);
			e.noRemove |= removeThis;
			result |= removeThis;
		}
		return result;
	}

	scan(set);
}

void applyNoRemoveRegex(string[] noRemoveStr)
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

void loadCoverage(string dir)
{
	foreach (ref f; set)
	{
		auto fn = std.path.join(dir, addExt(basename(f.filename), "lst"));
		if (!exists(fn))
			continue;
		writeln("Loading coverage file ", fn);

		static bool covered(string line)
		{
			enforce(line.length >= 8 && line[7]=='|', "Invalid syntax in coverage file");
			line = line[0..7];
			return line != "0000000" && line != "       ";
		}

		auto lines = map!covered(splitlines(cast(string)read(fn))[0..$-1]);
		uint line = 0;

		bool coverString(string s)
		{
			bool result;
			foreach (char c; s)
			{
				result |= lines[line];
				if (c == '\n')
					line++;
			}
			return result;
		}

		bool cover(ref Entity e)
		{
			bool result;
			result |= coverString(e.head);
			foreach (ref c; e.children)
				result |= cover(c);
			result |= coverString(e.tail);

			e.noRemove |= result;
			return result;
		}

		foreach (ref c; f.children)
			f.noRemove |= cover(c);
	}
}

void dumpSet(string fn)
{
	auto f = File(fn, "wt");

	string printable(string s)
	{
		return s is null ? "null" : `"` ~ s.replace("\\", `\\`).replace("\"", `\"`).replace("\r", `\r`).replace("\n", `\n`) ~ `"`;
	}

	void print(Entity[] entities, int depth)
	{
		auto prefix = replicate("  ", depth);
		foreach (e; entities)
		{
			if (e.children.length == 0)
			{
				f.writeln(prefix, "[", e.noRemove ? "!" : "", " ", e.head ? printable(e.head) ~ " " : null, e.tail ? printable(e.tail) ~ " " : null, "]");
			}
			else
			{
				f.writeln(prefix, "[", e.noRemove ? "!" : "", e.isPair ? " // Pair" : null);
				if (e.head) f.writeln(prefix, "  ", printable(e.head));
				print(e.children, depth+1);
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
