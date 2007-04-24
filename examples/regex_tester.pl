#!/usr/bin/perl

use strict;
use warnings;

# regex_tester.pl - Simple regular expression tester.
# Eric Saunders, Febuary 2007.

# Insert regex to test here...
my $pattern = shift || '^status\s*=\s*(.*)';

print "**********Eric's Simple Regex Tester**********\n";
print "Current regex is: |$pattern|\n";
print "> ";

# Cycle over user input and compare with pattern...
while (<>) {
    chomp;

    if ( my @captured = m/$pattern/o ) {
	print "Matched:  |$`<$&>$'|\n";
        print "Captured: <$_>\n" foreach @captured;
    } else {
	print "No match.\n";
    }
    print "> ";

}
