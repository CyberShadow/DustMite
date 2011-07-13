/// Very simplistic D source code "parser"
/// Written by Vladimir Panteleev <vladimir@thecybershadow.net>
/// Released into the Public Domain

module dsplit;

import std.file;
import std.path;
import std.string;
import std.array;
import std.ascii;
debug import std.stdio;

struct Entity
{
	string head;
	Entity[] children;
	string tail;

	bool isPair;           /// internal hint
	bool noRemove;         /// don't try removing this entity (children OK)

	alias head filename; // for depth 0
}

Entity[] loadFiles(ref string path, bool stripComments)
{
	if (isfile(path))
	{
		auto filePath = path;
		path = getName(path) is null ? path : getName(path);
		return [Entity(basename(filePath), loadFile(filePath, stripComments), null)];
	}
	else
	{
		Entity[] set;
		foreach (string entry; dirEntries(path, SpanMode.depth))
			if (isfile(entry))
			{
				assert(entry.startsWith(path));
				auto name = entry[path.length+1..$];
				set ~= Entity(name, loadFile(entry, stripComments), null);
			}
		return set;
	}
}

private:

Entity[] loadFile(string path, bool stripComments)
{
	string contents = cast(string)read(path);
	switch (getExt(path))
	{
	case "d":
		debug writeln("Loading ", path);
		if (stripComments)
			contents = stripDComments(contents);
		return parseD(contents);
	// One could add custom splitters for other languages here - for example, a simple line/word/character splitter for most text-based formats
	default:
		return [Entity(contents, null, null)];
	}
}

string skipSymbol(string s, ref size_t i)
{
	auto start = i;
	switch (s[i])
	{
	case '\'':
		i++;
		if (s[i] == '\\')
			i+=2;
		while (s[i] != '\'')
			i++;
		i++;
		break;
	case '\\':
		i+=2;
		break;
	case '"':
		if (i && s[i-1] == 'r')
		{
			i++;
			while (s[i] != '"')
				i++;
			i++;
		}
		else
		{
			i++;
			while (s[i] != '"')
			{
				if (s[i] == '\\')
					i+=2;
				else
					i++;
			}
			i++;
		}
		break;
	case '`':
		i++;
		while (s[i] != '`')
			i++;
		i++;
		break;
	case '/':
		i++;
		if (s[i] == '/')
		{
			while (i < s.length && s[i] != '\r' && s[i] != '\n')
				i++;
		}
		else
		if (s[i] == '*')
		{
			i+=3;
			while (s[i-2] != '*' || s[i-1] != '/')
				i++;
		}
		else
		if (s[i] == '+')
		{
			i++;
			int commentLevel = 1;
			while (commentLevel)
			{
				if (s[i] == '/' && s[i+1]=='+')
					commentLevel++, i+=2;
				else
				if (s[i] == '+' && s[i+1]=='/')
					commentLevel--, i+=2;
				else
					i++;
			}
		}
		else
			i++;
		break;
	default:
		i++;
		break;
	}
	return s[start..i];
}

/// Moves i forward over first series of EOL characters, or until first non-whitespace character
void skipToEOL(string s, ref size_t i)
{
	while (i < s.length)
	{
		if (s[i] == '\r' || s[i] == '\n')
		{
			while (i < s.length && (s[i] == '\r' || s[i] == '\n'))
				i++;
			return;
		}
		else
		if (isWhite(s[i]))
			i++;
		else
		if (s[i..$].startsWith("//"))
			skipSymbol(s, i);
		else
			break;
	}
}

/// Moves i backwards to the beginning of the current line, but not any further than start
void backToEOL(string s, ref size_t i, size_t start)
{
	while (i>start && isWhite(s[i-1]) && s[i-1] != '\n')
		i--;
}

Entity[] parseD(string s)
{
	size_t i = 0;
	size_t start;
	string innerTail;

	Entity[] parseScope(char end)
	{
		enum MAX_SPLITTER_LEVELS = 4;
		struct DSplitter { char open, close, sep; }
		static const DSplitter[MAX_SPLITTER_LEVELS] splitters = [{'{','}',';'}, {'(',')'}, {'[',']'}, {sep:','}];

		Entity[][MAX_SPLITTER_LEVELS] splitterQueue;

		Entity[] terminateLevel(int level)
		{
			if (level == MAX_SPLITTER_LEVELS)
			{
				auto text = s[start..i];
				start = i;
				return splitText(text);
			}
			else
			{
				auto next = terminateLevel(level+1);
				if (next.length <= 1)
					splitterQueue[level] ~= next;
				else
					splitterQueue[level] ~= Entity(null, next, null);
				auto r = splitterQueue[level];
				splitterQueue[level] = null;
				return r;
			}
		}

		string terminateText()
		{
			auto r = s[start..i];
			start = i;
			return r;
		}

		characterLoop:
		while (i < s.length)
		{
			char c = s[i];
			foreach (level, info; splitters)
				if (info.sep && c == info.sep)
				{
					auto children = terminateLevel(level+1);
					assert(i == start);
					i++; skipToEOL(s, i);
					splitterQueue[level] ~= Entity(null, children, terminateText());
					continue characterLoop;
				}
				else
				if (info.open && c == info.open)
				{
					auto openPos = i;
					backToEOL(s, i, start);
					auto pairHead = terminateLevel(level+1);

					i = openPos+1; skipToEOL(s, i);
					auto startSequence = terminateText();
					auto bodyContents = parseScope(info.close);

					auto pairBody = Entity(startSequence, bodyContents, innerTail);

					if (pairHead.length == 0)
						splitterQueue[level] ~= pairBody;
					else
					if (pairHead.length == 1)
						splitterQueue[level] ~= Entity(null, pairHead ~ pairBody, null, true);
					else
						splitterQueue[level] ~= Entity(null, [Entity(null, pairHead, null), pairBody], null, true);
					continue characterLoop;
				}

			if (end && c == end)
			{
				auto closePos = i;
				backToEOL(s, i, start);
				auto result = terminateLevel(0);
				i = closePos+1; skipToEOL(s, i);
				innerTail = terminateText();
				return result;
			}
			else
				skipSymbol(s, i);
		}

		innerTail = null;
		return terminateLevel(0);
	}

	auto result = parseScope(0);
	postProcessD(result);
	return result;
}

string stripDComments(string s)
{
	auto result = appender!string();
	size_t i = 0;
	while (i < s.length)
	{
		auto sym = skipSymbol(s, i);
		if (!sym.startsWithComment())
			result.put(sym);
	}
	return result.data;
}

/// Group together consecutive entities which might represent a single language construct
/// There is no penalty for false positives, so accuracy is not very important
void postProcessD(ref Entity[] entities)
{
	for (int i=0; i<entities.length;)
	{
		if (i+2 <= entities.length && entities.length > 2 && (
		    (getHeadText(entities[i]).startsWithWord("do") && getHeadText(entities[i+1]).isWord("while"))
		 || (getHeadText(entities[i]).startsWithWord("try") && getHeadText(entities[i+1]).startsWithWord("catch"))
		 || (getHeadText(entities[i]).startsWithWord("try") && getHeadText(entities[i+1]).startsWithWord("finally"))
		 || (getHeadText(entities[i+1]).isWord("in"))
		 || (getHeadText(entities[i+1]).isWord("out"))
		 || (getHeadText(entities[i+1]).isWord("body"))
		))
			entities.replaceInPlace(i, i+2, [Entity(null, entities[i..i+2].dup, null)]);
		else
		{
			postProcessD(entities[i].children);
			i++;
		}
	}
}

const bool[string] wordsToSplit;
static this() { wordsToSplit = ["else":true]; }

Entity[] splitText(string s)
{
	Entity[] result;
	while (s.length)
	{
		auto word = firstWord(s);
		if (word in wordsToSplit)
		{
			size_t p = word.ptr + word.length - s.ptr;
			skipToEOL(s, p);
			result ~= Entity(s[0..p], null, null);
			s = s[p..$];
		}
		else
		{
			result ~= Entity(s, null, null);
			s = null;
		}
	}

	return result;
}

string stripD(string s)
{
	size_t i=0;
	size_t start=s.length, end=s.length;
	while (i < s.length)
	{
		if (s[i..$].startsWithComment())
			skipSymbol(s, i);
		else
		if (!isWhite(s[i]))
		{
			if (start > i)
				start = i;
			skipSymbol(s, i);
			end = i;
		}
		else
			i++;
	}
	return s[start..end];
}

string firstWord(string s)
{
	size_t i = 0;
	s = stripD(s);
	while (i<s.length && !isWhite(s[i]))
		i++;
	return s[0..i];
}

bool startsWithWord(string s, string word)
{
	s = stripD(s);
	return s.startsWith(word) && (s.length == word.length || !isWordChar(s[word.length]));
}

bool endsWithWord(string s, string word)
{
	s = stripD(s);
	return s.endsWith(word) && (s.length == word.length || !isWordChar(s[$-word.length-1]));
}

bool isWord(string s, string word)
{
	return stripD(s) == word;
}

bool startsWithComment(string s)
{
	return s.startsWith("//") || s.startsWith("/*") || s.startsWith("/+");
}

string getHeadText(in Entity e)
{
	if (e.head)
		return e.head;
	foreach (ref child; e.children)
	{
		string s = getHeadText(child);
		if (s)
			return s;
	}
	if (e.tail)
		return e.tail;
	return null;
}

bool isWordChar(char c)
{
	return c=='_' || (c>='0' && c<='9') || (c>='a' && c<='z') || (c>='A' && c<='Z') || c>0x7F /* utf code-unit */;
}
