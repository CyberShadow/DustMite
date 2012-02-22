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
import std.ascii;
import std.random;

import dsplit;

alias std.string.join join;

string dir, resultDir, tester, globalCache;
Entity[] set;

struct Times { Duration load, testSave, resultSave, test, clean, cacheHash, misc; }
Times times;
SysTime lastTime;
Duration elapsedTime() { auto c = Clock.currTime(); auto d = c - lastTime; lastTime = c; return d; }
void measure(string what)(void delegate() p) { times.misc += elapsedTime(); p(); mixin("times."~what~" += elapsedTime();"); }
int tests; bool foundAnything;
bool noSave;

struct Reduction
{
	enum Type { None, Remove, Unwrap, ReplaceWord }
	Type type;

	// Remove / Unwrap
	uint[] address;

	// ReplaceWord
	string from, to;
	int index, total;

	string toString()
	{
		string name = .to!string(type);

		final switch (type)
		{
			case Reduction.Type.None:
				return name;
			case Reduction.Type.ReplaceWord:
				return format(`%s [%d/%d: %s -> %s]`, name, index+1, total, from, to);
			case Reduction.Type.Remove:
			case Reduction.Type.Unwrap:
				string[] segments = new string[address.length];
				Entity[] e = set;
				foreach (i, a; address)
				{
					segments[i] = format("%d/%d", e.length-a, e.length);
					e = e[a].children;
				}
				return name ~ " [" ~ segments.join(", ") ~ "]";
		}
	}
}

auto nullReduction = Reduction(Reduction.Type.None);

int main(string[] args)
{
	bool force, dump, showTimes, stripComments, obfuscate, keepLength, showHelp;
	string coverageDir;
	string[] noRemoveStr;

	getopt(args,
		"force", &force,
		"noremove", &noRemoveStr,
		"strip-comments", &stripComments,
		"coverage", &coverageDir,
		"obfuscate", &obfuscate,
		"keep-length", &keepLength,
		"dump", &dump,
		"times", &showTimes,
		"cache", &globalCache, // for research
		"nosave", &noSave, // for research
		"h|help", &showHelp
	);

	if (showHelp || args.length == 1 || args.length>3)
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
  --obfuscate        Instead of reducing, obfuscates the input by replacing
                       words with random substitutions
  --keep-length      Preserve word length when obfuscating
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

	bool isDotName(string fn) { return fn.startsWith(".") && !(fn=="." || fn==".."); }

	if (!force && isDir(dir))
		foreach (string path; dirEntries(dir, SpanMode.breadth))
			if (isDotName(basename(path)) || isDotName(basename(dirname(path))) || getExt(path)=="o" || getExt(path)=="obj" || getExt(path)=="exe")
			{
				stderr.writefln("Suspicious file found: %s\nYou should use a clean copy of the source tree.\nIf it was your intention to include this file in the file-set to be reduced,\nre-run dustmite with the --force option.", path);
				return 1;
			}

	auto startTime = lastTime = Clock.currTime();

	ParseOptions parseOptions;
	parseOptions.stripComments = stripComments;
	parseOptions.mode = obfuscate ? ParseOptions.Mode.Words : ParseOptions.Mode.Source;
	measure!"load"({set = loadFiles(dir, parseOptions);});
	enforce(set.length, "No files in specified directory");

	optimize(set);
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

	resultDir = dir ~ ".reduced";
	enforce(!exists(resultDir), "Result directory already exists");

	if (!test(Reduction(Reduction.Type.None)))
		throw new Exception("Initial test fails");

	foundAnything = false;
	if (obfuscate)
		.obfuscate(keepLength);
	else
		reduce();

	auto duration = Clock.currTime()-startTime;
	duration = dur!"msecs"(duration.total!"msecs"); // truncate anything below ms, users aren't interested in that
	if (foundAnything)
	{
		if (noSave)
			measure!"resultSave"({safeSave(resultDir);});
		writefln("Done in %s tests and %s; reduced version is in %s", tests, duration, resultDir);
	}
	else
		writefln("Done in %s tests and %s; no reductions found", tests, duration);

	if (showTimes)
		foreach (i, t; times.tupleof)
			writefln("%s: %s", times.tupleof[i].stringof, times.tupleof[i]);

	return 0;
}

void reduceScan(ref Entity[] set, int testDepth, out bool tested, out bool changed)
{
	tested = changed = false;

	enum MAX_DEPTH = 1024;
	uint[MAX_DEPTH] address;

	void scan(ref Entity[] entities, int depth)
	{
		foreach_reverse (i; 0..entities.length)
		{
			address[depth] = i;
			if (depth < testDepth)
			{
				// recurse
				scan(entities[i].children, depth+1);
			}
			else
			if (entities[i].noRemove)
			{
				// skip, but don't stop going deeper
				tested = true;
			}
			else
			{
				// test
				tested = true;
				if (test(Reduction(Reduction.Type.Remove, address[0..depth+1])))
				{
					entities = remove(entities, i);
					saveResult();
					changed = true;
				}
				else
				if (entities[i].head.length && entities[i].tail.length && test(Reduction(Reduction.Type.Unwrap, address[0..depth+1])))
				{
					entities[i].head = entities[i].tail = null;
					saveResult();
					changed = true;
				}
			}
		}
	}

	scan(set, 0);

	//writefln("Scan results: tested=%s, changed=%s", tested, changed);
}

/// Keep going deeper until we find a successful reduction.
/// When found, finish tests at current depth and restart from top depth (new iteration).
/// If we reach the bottom (depth with no nodes on it), we're done.
void reduceCareful()
{
	bool tested;
	int iterCount;
	do
	{
		writefln("############### ITERATION %d ################", iterCount++);
		bool changed;
		int testDepth = 0;
		do
		{
			writefln("============= Depth %d =============", testDepth);

			reduceScan(set, testDepth, tested, changed);

			testDepth++;
		} while (tested && !changed); // go deeper while we found something to test, but no results
	} while (tested); // stop when we didn't find anything to test
}

/// Keep going deeper until we find a successful reduction.
/// When found, go up a depth level.
/// Keep going up while we find new reductions. Repeat topmost depth level as necessary.
/// Once no new reductions are found at higher depths, jump to the next unvisited depth in this iteration.
/// If we reach the bottom (depth with no nodes on it), start a new iteration.
/// If we finish an iteration without finding anything, we're done.
void reduceLookback()
{
	bool iterationChanged;
	int iterCount;
	do
	{
		iterationChanged = false;
		writefln("############### ITERATION %d ################", iterCount++);

		int testDepth = 0, maxDepth = 0;
		bool depthTested;

		do
		{
			writefln("============= Depth %d =============", testDepth);
			bool depthChanged;

			reduceScan(set, testDepth, depthTested, depthChanged);

			if (depthChanged)
			{
				iterationChanged = true;
				testDepth--;
				if (testDepth < 0)
					testDepth = 0;
			}
			else
			{
				maxDepth++;
				testDepth = maxDepth;
			}
		} while (depthTested); // keep going up/down while we found something to test
	} while (iterationChanged); // stop when we couldn't reduce anything this iteration
}

void reduce()
{
	//reduceIterative();
	reduceLookback();
}

void obfuscate(bool keepLength)
{
	bool[string] wordSet;
	string[] words; // preserve file order

	foreach (f; set)
	{
		foreach (ref entity; parseToWords(f.filename) ~ f.children)
			if (entity.head.length && !isDigit(entity.head[0]))
				if (entity.head !in wordSet)
				{
					wordSet[entity.head] = true;
					words ~= entity.head;
				}
	}

	string idgen(uint length)
	{
		static const first = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"; // use caps to avoid collisions with reserved keywords
		static const other = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_";

		if (keepLength)
		{
			auto result = new char[length];
			foreach (i, ref c; result)
				c = (i==0 ? first : other)[uniform(0, $)];

			return assumeUnique(result);
		}
		else
		{
			static int index;
			index++;

			string result;
			result ~= first[index % $];
			index /= first.length;

			while (index)
				result ~= other[index % $],
				index /= other.length;

			return result;
		}
	}

	auto r = Reduction(Reduction.Type.ReplaceWord);
	r.total = cast(uint) words.length;
	foreach (int i, word; words)
	{
		r.index = i;
		r.from = word;
		int tries = 0;
		do
			r.to = idgen(cast(uint) word.length);
		while (r.to in wordSet && tries++ < 10);
		wordSet[r.to] = true;

		if (test(r))
		{
			foreach (ref f; set)
			{
				f.filename = applyReductionToPath(f.filename, r);
				foreach (ref entity; f.children)
					if (entity.head == r.from)
						entity.head = r.to;
			}
			saveResult();
		}
	}
}

void dump(Entity[] entities, ref Reduction reduction, void delegate(string) writer, bool fileLevel)
{
	auto childReduction = reduction;

	foreach (i, ref e; entities)
	{
		if (reduction.type == Reduction.Type.ReplaceWord)
		{
			if (fileLevel)
			{
				writer(applyReductionToPath(e.filename, reduction));
				dump(e.children, reduction, writer, false);
				assert(e.tail.length==0);
			}
			else
			{
				assert(e.children.length==0);
				if (e.head == reduction.from)
					writer(reduction.to);
				else
					writer(e.head);
				writer(e.tail);
			}
		}
		else
		if (reduction.address.length==1 && reduction.address[0]==i)
		{
			final switch (reduction.type)
			{
			case Reduction.Type.None:
			case Reduction.Type.ReplaceWord:
				assert(0);
			case Reduction.Type.Remove: // skip this entity
				continue;
			case Reduction.Type.Unwrap: // skip head/tail
				dump(e.children, nullReduction, writer, false);
				break;
			}
		}
		else
		{
			if (e.head.length) writer(e.head);
			childReduction.address = reduction.address.length>1 && reduction.address[0]==i ? reduction.address[1..$] : null;
			dump(e.children, childReduction, writer, false);
			if (e.tail.length) writer(e.tail);
		}
	}
}

void save(Reduction reduction, string savedir)
{
	enforce(!exists(savedir), "Directory already exists: " ~ savedir);
	mkdirRecurse(savedir);
	auto childReduction = reduction;

	foreach (i, f; set)
	{
		if (reduction.address.length==1 && reduction.address[0]==i) // skip this file
		{
			assert(reduction.type == Reduction.Type.Remove);
			continue;
		}

		auto path = std.path.join(savedir, applyReductionToPath(f.filename, reduction));
		if (!exists(dirname(path)))
			mkdirRecurse(dirname(path));

		auto o = File(path, "wb");
		childReduction.address = reduction.address.length>1 && reduction.address[0]==i ? reduction.address[1..$] : null;
		dump(f.children, childReduction, &o.write!string, false);
		o.close();
	}
}

string applyReductionToPath(string path, Reduction reduction)
{
	if (reduction.type == Reduction.Type.ReplaceWord)
	{
		Entity[] words = parseToWords(path);
		string result;
		foreach (i, ref word; words)	
		{
			if (i > 0 && i == words.length-1 && words[i-1].tail.endsWith("."))
				result ~= word.head; // skip extension
			else
			if (word.head == reduction.from)
				result ~= reduction.to;
			else
				result ~= word.head;
			result ~= word.tail;
		}
		return result;
	}
	return path;
}

void safeRmdirRecurse(string dir)
{
	while (true)
		try
		{
			rmdirRecurse(dir);
			return;
		}
		catch (Exception e)
		{
			writeln("Error while rmdir-ing " ~ dir ~ ": " ~ e.msg);
			import core.thread;
			Thread.sleep(dur!"seconds"(1));
			writeln("Retrying...");
		}
}

void safeSave(string savedir)
{
	auto tempdir = savedir ~ ".inprogress"; scope(failure) safeRmdirRecurse(tempdir);
	if (exists(tempdir)) safeRmdirRecurse(tempdir);
	save(Reduction(Reduction.Type.None), tempdir);
	if (exists(savedir)) safeRmdirRecurse(savedir);
	rename(tempdir, savedir);
}

void saveResult()
{
	if (!noSave)
		measure!"resultSave"({safeSave(resultDir);});
}

version(HAVE_AE)
{
	// Use faster murmurhash from http://github.com/CyberShadow/ae
	// when compiled with -version=HAVE_AE

	import ae.utils.digest;
	import ae.utils.textout;

	alias MH3Digest128 HASH;

	HASH hash(Reduction reduction)
	{
		static StringBuffer sb;
		sb.clear();
		dump(set, reduction, &sb.put!string, true);
		return murmurHash3_128(sb.get());
	}

	alias digestToStringMH3 formatHash;
}
else
{
	import std.md5;

	alias ubyte[16] HASH;

	HASH hash(Reduction reduction)
	{
		ubyte[16] digest;
		MD5_CTX context;
		context.start();
		dump(set, reduction, cast(void delegate(string))&context.update, true);
		context.finish(digest);
		return digest;
	}

	alias digestToString formatHash;
}

bool[HASH] cache;

bool test(Reduction reduction)
{
	write(reduction, " => "); stdout.flush();

	HASH digest;
	measure!"cacheHash"({ digest = hash(reduction); });

	bool ramCached(lazy bool fallback)
	{
		auto cacheResult = digest in cache;
		if (cacheResult)
		{
			// Note: as far as I can see, a cache hit for a positive reduction is not possible (except, perhaps, for a no-op reduction)
			writeln(*cacheResult ? "Yes" : "No", " (cached)");
			return *cacheResult;
		}
		auto result = fallback;
		return cache[digest] = result;
	}

	bool diskCached(lazy bool fallback)
	{
		tests++;

		if (globalCache)
		{
			string cacheBase = absolutePath(buildPath(globalCache, formatHash(digest))) ~ "-";
			if (exists(cacheBase~"0"))
			{
				writeln("No (disk cache)");
				return false;
			}
			if (exists(cacheBase~"1"))
			{
				writeln("Yes (disk cache)");
				return true;
			}
			auto result = fallback;
			std.file.write(cacheBase ~ (result ? "1" : "0"), "");
			return result;
		}
		else
			return fallback;
	}

	bool doTest()
	{
		string testdir = dir ~ ".test";
		measure!"testSave"({save(reduction, testdir);}); scope(exit) measure!"clean"({safeRmdirRecurse(testdir);});

		auto lastdir = getcwd(); scope(exit) chdir(lastdir);
		chdir(testdir);

		bool result;
		measure!"test"({result = system(tester) == 0;});
		writeln(result ? "Yes" : "No");
		return result;
	}

	auto result = ramCached(diskCached(doTest()));
	if (result)
		foundAnything = true;
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

		auto lines = map!covered(splitLines(cast(string)read(fn))[0..$-1]);
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
