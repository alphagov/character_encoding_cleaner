# Character Encoding Cleaner

## Introduction

This script is for fixing illegal encodings in text files. It's designed to clean up corrupt character sequences in UTF-8 files. The most common cause of such corruption is opening a UTF-8 encoded file as though it were ISO-8859-1, and then saving it as UTF-8. This double-encodes the UTF-8 byte sequences.

This script makes no attempt to intelligently reverse such double encoding. Rather it detects and displays sequences of non-ascii characters (0x80-0xFF) in context, and allows the user to enter mappings for each of these in a mappings file.

Any byte sequence which is a known target of a mapping is allowed to remain in the output file.

## Required gems

 * gem install colorize

## Usage

Imagine you have a file with corrupted encodings called `badchars.csv`. Invoke the script like this:

```
$ ./clean_encoding.rb badchars.csv fixed.csv
```

This tells the script to read `badchars.csv`, apply any known mappings (read from `mappings.txt`) and output the result to `fixed.csv`.

If an unknown sequence of non-ascii characters is detected, it will be displayed, highlighted in red, with a bit of context. The `mappings.txt` file will be updated with the new mapping and 'TODO'.

```
\xC3\x83\xC6\x92\xC3\x82\xE2\x80\x9A\xC3\x83\xE2\x80\x9A\xC3\x82\xC2\xA3:TODO
```

simply edit the file to indicate the desired replacement:

```
\xC3\x83\xC6\x92\xC3\x82\xE2\x80\x9A\xC3\x83\xE2\x80\x9A\xC3\x82\xC2\xA3:£
```

The `mappings.txt` file should be UTF-8 encoded, so that the replacements can be displayed and edited correctly.