/// Very simplistic D source code "parser"
/// Written by Vladimir Panteleev <vladimir@thecybershadow.net>
/// Released into the Public Domain

module dsplit;

import std.file;
import std.path;
import std.string;
import std.ctype;
import std.array;
debug import std.stdio;

struct Entity
{
	string head;
	Entity[] children;
	string tail;

	bool isPair;           /// internal hint
	bool noRemove;         /// don't try removing this entity (children OK)

	alias head filename; // for level 0
}

Entity[] loadFiles(string dir)
{
	Entity[] set;
	foreach (path; listdir(dir, "*"))
		if (isfile(path))
		{
			assert(path.startsWith(dir));
			auto name = path[dir.length+1..$];
			set ~= Entity(name, loadFile(path), null);
		}
	return set;
}

private:

Entity[] loadFile(string path)
{
	string contents = cast(string)read(path);
	switch (getExt(path))
	{
	case "d":
		debug writeln("Loading ", path);
		return parseD(contents);
	// One could add custom splitters for other languages here - for example, a simple line/word/character splitter for most text-based formats
	default:
		return [Entity(contents, null, null)];
	}
}

Entity[] parseD(string s)
{
	size_t i = 0;
	size_t start;
	string innerTail;

	/// Moves i forward over first series of EOL characters, or until first non-whitespace character
	void skipToEOL()
	{
		// TODO: skip end-of-line comments, too
		while (i < s.length && iswhite(s[i]))
		{
			if (s[i] == '\r' || s[i] == '\n')
			{
				while (i < s.length && (s[i] == '\r' || s[i] == '\n'))
					i++;
				return;
			}
			i++;
		}
	}

	/// Moves i backwards to the start of the current line
	void backToEOL()
	{
		while (i>start && iswhite(s[i-1]) && s[i-1] != '\n')
			i--;
	}

	void skipSymbol()
	{
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
		case '"':
			if (s[i-1] == 'r')
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
				while (s[i] != '\r' && s[i] != '\n')
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
	}

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
				if (text.length)
					return [Entity(text, null, null)];
				else
					return null;
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
					i++; skipToEOL();
					splitterQueue[level] ~= Entity(null, children, terminateText());
					continue characterLoop;
				}
				else
				if (info.open && c == info.open)
				{
					auto openPos = i;
					backToEOL();
					auto pairHead = terminateLevel(level+1);

					i = openPos+1; skipToEOL();
					auto startSequence = terminateText();
					auto bodyContents = parseScope(info.close);

					auto pairBody = Entity(startSequence, bodyContents, innerTail);

					splitterQueue[level] ~= pairHead ? Entity(null, [Entity(null, pairHead, null), pairBody], null, true) : pairBody;
					continue characterLoop;
				}

			if (end && c == end)
			{
				auto closePos = i;
				backToEOL();
				auto result = terminateLevel(0);
				i = closePos+1; skipToEOL();
				innerTail = terminateText();
				return result;
			}
			else
				skipSymbol();
		}

		innerTail = null;
		return terminateLevel(0);
	}

	return parseScope(0);
}

/+
/// Group together consecutive entities which might represent a single language construct
/// There is no penalty for false positives, so accuracy is not very important
Entity[] postProcessD(Entity[] entities)
{
	for (int i=0; i<entities.length; i++)
	{
		if (i+3 <= entities.length && entities[i].isPair && entities[i+1].isPair && entities[i+2].isPair && (
			(entities[i].children[0].head.endsWithWord("in")  && entities[i+1].children[0].head.endsWithWord("out") && entities[i+2].children[0].head.endsWithWord("body")) ||
			(entities[i].children[0].head.endsWithWord("out") && entities[i+1].children[0].head.endsWithWord("in")  && entities[i+2].children[0].head.endsWithWord("body"))
		))
			entities.replaceInPlace(i, i+3, [Entity(null, entities[i..i+3].dup, null)]);
		else
		if (i+2 <= entities.length && entities[i].isPair && entities[i+1].isPair && (
			(entities[i].children[0].head.endsWithWord("in")  && entities[i+1].children[0].head.endsWithWord("body")) ||
			(entities[i].children[0].head.endsWithWord("out") && entities[i+1].children[0].head.endsWithWord("body")) ||
			(entities[i].children[0].head.endsWithWord("try") && entities[i+1].children[0].head.startsWithWord("catch")) ||
			(entities[i].children[0].head.endsWithWord("try") && entities[i+1].children[0].head.startsWithWord("finally"))
		))
			entities.replaceInPlace(i, i+2, [Entity(null, entities[i..i+2].dup, null)]);
		else
		if (i+2 <= entities.length && entities[i+1].head.startsWithWord("while") && entities[i+1].children is null && (
			(entities[i].isPair && entities[i].children[0].head.isWord("do")) ||
			(entities[i].head.startsWithWord("do"))
		))
			entities.replaceInPlace(i, i+2, [Entity(null, entities[i..i+2].dup, null)]);
	}

	return entities;
}

string stripD(string s)
{
	// TODO: strip D comments, too
	return strip(s);
}

bool startsWithWord(string s, string word)
{
	s = stripD(s);
	return s.startsWith(word) && (s.length == word.length || !isalnum(s[word.length]));
}

bool endsWithWord(string s, string word)
{
	s = stripD(s);
	return s.endsWith(word) && (s.length == word.length || !isalnum(s[$-word.length-1]));
}

bool isWord(string s, string word)
{
	// TODO: fixme
	return s.startsWithWord(word) || s.endsWithWord(word);
}
+/