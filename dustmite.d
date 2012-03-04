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
size_t maxBreadth;
Entity root;

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
	size_t[] address;
	Entity target;

	// ReplaceWord
	string from, to;
	size_t index, total;

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
				Entity e = root;
				real progress = 0.0, progressFraction = 100.0;
				bool binary = maxBreadth == 2;
				foreach (i, a; address)
				{
					segments[i] = binary ? text(a) : format("%d/%d", e.children.length-a, e.children.length);
					progressFraction /= e.children.length;
					progress += progressFraction * (e.children.length-a-1);
					e = e.children[a];
				}
				return format("[%5.1f%%] %s [%s]", progress, name, segments.join(binary ? "" : ", "));
		}
	}
}

auto nullReduction = Reduction(Reduction.Type.None);

int main(string[] args)
{
	bool force, dump, showTimes, stripComments, obfuscate, keepLength, showHelp, noOptimize;
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
		"nosave|no-save", &noSave, // for research
		"no-optimize", &noOptimize, // for research
		"h|help", &showHelp
	);

	if (showHelp || args.length == 1 || args.length>3)
	{
		stderr.writef(q"EOS
Usage: %s [OPTION]... PATH TESTER
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
EOS", args[0]);

		if (!showHelp)
		{
			stderr.write(q"EOS
  --help             Show this message and some less interesting options
EOS");
		}
		else
		{
			stderr.write(q"EOS
  --help             Show this message
Less interesting options:
  --dump             Dump parsed tree to DIR.dump file
  --times            Display verbose spent time breakdown
  --cache DIR        Use DIR as persistent disk cache
                       (in addition to memory cache)
  --no-save          Disable saving in-progress result
  --no-optimize      Disable tree optimization step
                       (may be useful with --dump)
EOS");
		}
		return showHelp ? 0 : 64; // EX_USAGE
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
	measure!"load"({root = loadFiles(dir, parseOptions);});
	enforce(root.children.length, "No files in specified directory");

	if (!obfuscate && !noOptimize)
		optimize(root);
	applyNoRemoveMagic();
	applyNoRemoveRegex(noRemoveStr);
	if (coverageDir)
		loadCoverage(coverageDir);
	maxBreadth = getMaxBreadth(root);

	if (dump)
		dumpSet(dir ~ ".dump");

	if (tester is null)
	{
		writeln("No tester specified, exiting");
		return 0;
	}

	resultDir = dir ~ ".reduced";
	enforce(!exists(resultDir), "Result directory already exists");

	if (!test(nullReduction))
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

size_t getMaxBreadth(Entity e)
{
	size_t breadth = e.children.length;
	foreach (child; e.children)
	{
		auto childBreadth = getMaxBreadth(child);
		if (breadth < childBreadth)
			breadth = childBreadth;
	}
	return breadth;
}

/// Try reductions at address. Edit set, save result and return true on successful reduction.
bool testAddress(size_t[] address)
{
	auto e = entityAt(address);

	if (tryReduction(Reduction(Reduction.Type.Remove, address, e)))
		return true;
	else
	if (e.head.length && e.tail.length && tryReduction(Reduction(Reduction.Type.Unwrap, address, e)))
		return true;
	else
		return false;
}

void testLevel(int testDepth, out bool tested, out bool changed)
{
	tested = changed = false;

	enum MAX_DEPTH = 1024;
	size_t[MAX_DEPTH] address;

	void scan(Entity e, int depth)
	{
		if (depth < testDepth)
		{
			// recurse
			foreach_reverse (i, c; e.children)
			{
				address[depth] = i;
				scan(c, depth+1);
			}
		}
		else
		if (e.noRemove)
		{
			// skip, but don't stop going deeper
			tested = true;
		}
		else
		{
			// test
			tested = true;
			if (testAddress(address[0..depth]))
				changed = true;
		}
	}

	scan(root, 0);

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
		int depth = 0;
		do
		{
			writefln("============= Depth %d =============", depth);

			testLevel(depth, tested, changed);

			depth++;
		} while (tested && !changed); // go deeper while we found something to test, but no results
	} while (tested); // stop when we didn't find anything to test
}

/// Keep going deeper until we find a successful reduction.
/// When found, go up a depth level.
/// Keep going up while we find new reductions. Repeat topmost depth level as necessary.
/// Once no new reductions are found at higher depths, jump to the next unvisited depth in this iteration.
/// If we reach the bottom (depth with no nodes on it), start a new iteration.
/// If we finish an iteration without finding any reductions, we're done.
void reduceLookback()
{
	bool iterationChanged;
	int iterCount;
	do
	{
		iterationChanged = false;
		writefln("############### ITERATION %d ################", iterCount++);

		int depth = 0, maxDepth = 0;
		bool depthTested;

		do
		{
			writefln("============= Depth %d =============", depth);
			bool depthChanged;

			testLevel(depth, depthTested, depthChanged);

			if (depthChanged)
			{
				iterationChanged = true;
				depth--;
				if (depth < 0)
					depth = 0;
			}
			else
			{
				maxDepth++;
				depth = maxDepth;
			}
		} while (depthTested); // keep going up/down while we found something to test
	} while (iterationChanged); // stop when we couldn't reduce anything this iteration
}

/// Look at every entity in the tree.
/// If we can reduce this entity, continue looking at its siblings.
/// Otherwise, recurse and look at its children.
/// End an iteration once we looked at an entire tree.
/// If we finish an iteration without finding any reductions, we're done.
void reduceInDepth()
{
	bool changed;
	int iterCount;
	do
	{
		changed = false;
		writefln("############### ITERATION %d ################", iterCount++);

		enum MAX_DEPTH = 1024;
		size_t[MAX_DEPTH] address;

		void scan(Entity e, int depth)
		{
			if (e.noRemove)
			{
				// skip, but don't stop going deeper
			}
			else
			{
				// test
				if (testAddress(address[0..depth]))
				{
					changed = true;
					return;
				}
			}

			// recurse
			foreach_reverse (i, c; e.children)
			{
				address[depth] = i;
				scan(c, depth+1);
			}
		}

		scan(root, 0);
	} while (changed); // stop when we couldn't reduce anything this iteration
}

void reduce()
{
	//reduceIterative();
	//reduceLookback();
	reduceInDepth();
}

void obfuscate(bool keepLength)
{
	bool[string] wordSet;
	string[] words; // preserve file order

	foreach (f; root.children)
	{
		foreach (entity; parseToWords(f.filename) ~ f.children)
			if (entity.head.length && !isDigit(entity.head[0]))
				if (entity.head !in wordSet)
				{
					wordSet[entity.head] = true;
					words ~= entity.head;
				}
	}

	string idgen(size_t length)
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
	r.total = words.length;
	foreach (i, word; words)
	{
		r.index = i;
		r.from = word;
		int tries = 0;
		do
			r.to = idgen(word.length);
		while (r.to in wordSet && tries++ < 10);
		wordSet[r.to] = true;

		tryReduction(r);
	}
}

bool skipEntity(Entity e)
{
	if (e.removed)
		return true;
	foreach (dependency; e.dependencies)
		if (skipEntity(dependency))
			return true;
	return false;
}

void dump(Entity root, ref Reduction reduction, void delegate(string) handleFile, void delegate(string) handleText)
{
	void dumpEntity(Entity e)
	{
		if (reduction.type == Reduction.Type.ReplaceWord)
		{
			if (e.isFile)
			{
				assert(e.head.length==0 && e.tail.length==0);
				handleFile(applyReductionToPath(e.filename, reduction));
			}
			else
			if (e.head)
			{
				assert(e.children.length==0);
				if (e.head == reduction.from)
					handleText(reduction.to);
				else
					handleText(e.head);
				handleText(e.tail);
			}
			else
				foreach (c; e.children)
					dumpEntity(c);
		}
		else
		if (e is reduction.target)
		{
			final switch (reduction.type)
			{
			case Reduction.Type.None:
			case Reduction.Type.ReplaceWord:
				assert(0);
			case Reduction.Type.Remove: // skip this entity
				return;
			case Reduction.Type.Unwrap: // skip head/tail
				foreach (c; e.children)
					dumpEntity(c);
				break;
			}
		}
		else
		if (skipEntity(e))
			return;
		else
		if (e.isFile)
		{
			handleFile(e.filename);
			foreach (c; e.children)
				dumpEntity(c);
		}
		else
		{
			if (e.head.length) handleText(e.head);
			foreach (c; e.children)
				dumpEntity(c);
			if (e.tail.length) handleText(e.tail);
		}
	}

	debug verifyNotRemoved(root);
	if (reduction.type == Reduction.Type.Remove)
		markRemoved(reduction.target, true); // Needed for dependencies

	dumpEntity(root);

	if (reduction.type == Reduction.Type.Remove)
		markRemoved(reduction.target, false);
	debug verifyNotRemoved(root);
}

void save(Reduction reduction, string savedir)
{
	enforce(!exists(savedir), "Directory already exists: " ~ savedir);
	mkdirRecurse(savedir);

	File o;

	void handleFile(string fn)
	{
		auto path = std.path.join(savedir, fn);
		if (!exists(dirname(path)))
			mkdirRecurse(dirname(path));

		o.open(path, "wb");
	}

	dump(root, reduction, &handleFile, &o.write!string);
}

Entity entityAt(size_t[] address)
{
	Entity e = root;
	foreach (a; address)
		e = e.children[a];
	return e;
}

/// Try specified reduction. If it succeeds, apply it permanently and save intermediate result.
bool tryReduction(Reduction r)
{
	if (test(r))
	{
		debug
			auto hashBefore = hash(r);
		applyReduction(r);
		debug
		{
			auto hashAfter = hash(nullReduction);
			assert(hashBefore == hashAfter, "Reduction preview/application mismatch");
		}
		saveResult();
		return true;
	}
	return false;
}

void verifyNotRemoved(Entity e)
{
	assert(!e.removed);
	foreach (c; e.children)
		verifyNotRemoved(c);
}

void markRemoved(Entity e, bool value)
{
	assert(e.removed == !value);
	e.removed = value;
	foreach (c; e.children)
		markRemoved(c, value);
}

/// Permanently apply specified reduction to set.
void applyReduction(ref Reduction r)
{
	final switch (r.type)
	{
		case Reduction.Type.None:
			return;
		case Reduction.Type.ReplaceWord:
		{
			foreach (ref f; root.children)
			{
				f.filename = applyReductionToPath(f.filename, r);
				foreach (ref entity; f.children)
					if (entity.head == r.from)
						entity.head = r.to;
			}
			return;
		}
		case Reduction.Type.Remove:
		{
			debug verifyNotRemoved(root);

			markRemoved(entityAt(r.address), true);

			if (r.address.length)
			{
				auto p = entityAt(r.address[0..$-1]);
				p.children = remove(p.children, r.address[$-1]);
			}
			else
				root = new Entity();

			debug verifyNotRemoved(root);
			return;
		}
		case Reduction.Type.Unwrap:
			with (entityAt(r.address))
				head = tail = null;
			return;
	}
}

string applyReductionToPath(string path, Reduction reduction)
{
	if (reduction.type == Reduction.Type.ReplaceWord)
	{
		Entity[] words = parseToWords(path);
		string result;
		foreach (i, word; words)
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
	save(nullReduction, tempdir);
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
		auto writer = &sb.put!string;
		dump(root, reduction, writer, writer);
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
		auto writer = cast(void delegate(string))&context.update;
		dump(root, reduction, writer, writer);
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

	bool scan(Entity e)
	{
		bool removeThis;
		removeThis  = scanString(e.head);
		foreach (c; e.children)
			removeThis |= scan(c);
		removeThis |= scanString(e.tail);
		e.noRemove |= removeThis;
		return removeThis;
	}

	scan(root);
}

void applyNoRemoveRegex(string[] noRemoveStr)
{
	auto noRemove = map!regex(noRemoveStr);

	void mark(Entity e)
	{
		e.noRemove = true;
		foreach (c; e.children)
			mark(c);
	}

	bool scan(Entity e)
	{
		if (canFind!((a){return !match(e.head, a).empty || !match(e.tail, a).empty;})(noRemove))
		{
			e.noRemove = true;
			foreach (c; e.children)
				mark(c);
			return true;
		}
		else
		{
			bool found = false;
			foreach (c; e.children)
				if (scan(c))
					e.noRemove = found = true;
			return found;
		}
	}

	scan(root);
}

void loadCoverage(string dir)
{
	void scanFile(Entity f)
	{
		auto fn = std.path.join(dir, addExt(basename(f.filename), "lst"));
		if (!exists(fn))
			return;
		writeln("Loading coverage file ", fn);

		static bool covered(string line)
		{
			enforce(line.length >= 8 && line[7]=='|', "Invalid syntax in coverage file");
			line = line[0..7];
			return line != "0000000" && line != "       ";
		}

		auto lines = map!covered(splitLines(readText(fn))[0..$-1]);
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

	void scanFiles(Entity e)
	{
		if (e.isFile)
			scanFile(e);
		else
			foreach (c; e.children)
				scanFiles(c);
	}

	scanFiles(root);
}

void dumpSet(string fn)
{
	auto f = File(fn, "wt");

	string printable(string s, bool isFile)
	{
		if (isFile)
			return "/*** " ~ s ~ " ***/";
		else
			return s is null ? "null" : `"` ~ s.replace("\\", `\\`).replace("\"", `\"`).replace("\r", `\r`).replace("\n", `\n`) ~ `"`;
	}

	int counter;
	void assignID(Entity e)
	{
		e.id = counter++;
		foreach (c; e.children)
			assignID(c);
	}
	assignID(root);

	bool[int] dependents;
	void scanDependents(Entity e)
	{
		foreach (d; e.dependencies)
			dependents[d.id] = true;
		foreach (c; e.children)
			scanDependents(c);
	}
	scanDependents(root);

	void print(Entity e, int depth, bool fileLevel)
	{
		auto prefix = replicate("  ", depth);
		bool isFile = fileLevel && e.isFile;
		bool inFiles = fileLevel && !e.isFile;

		// if (!fileLevel) { f.writeln(prefix, "[ ... ]"); continue; }

		f.write(prefix);
		if (e.id in dependents)
			f.write(e.id, " ");
		if (e.dependencies.length)
		{
			f.write(" => ");
			foreach (d; e.dependencies)
				f.write(d.id, " ");
		}

		if (e.children.length == 0)
		{
			f.writeln("[", e.noRemove ? "!" : "", " ", e.head ? printable(e.head, isFile) ~ " " : null, e.tail ? printable(e.tail, isFile) ~ " " : null, "]");
		}
		else
		{
			f.writeln("[", e.noRemove ? "!" : "", e.isPair ? " // Pair" : null);
			if (e.head) f.writeln(prefix, "  ", printable(e.head, isFile));
			foreach (c; e.children)
				print(c, depth+1, inFiles);
			if (e.tail) f.writeln(prefix, "  ", printable(e.tail, isFile));
			f.writeln(prefix, "]");
		}
	}

	print(root, 0, true);

	f.close();
}

void dumpText(string fn, ref Reduction r = nullReduction)
{
	auto f = File(fn, "wt");
	dump(root, r, (string) {}, &f.write!string);
	f.close();
}
