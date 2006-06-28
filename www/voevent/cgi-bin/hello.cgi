#!/software/perl-5.8.6/bin/perl


# G R A B   K E Y W O R D S ---------------------------------------------------

my $string = $ENV{QUERY_STRING};
my @pairs = split( /&/, $string );

# loop through the query string passed to the script and seperate key
# value pairs, remembering to un-Webify the munged data
my %query;
foreach my $i ( 0 ... $#pairs ) {
   my ( $name, $value ) = split( /=/, $pairs[$i] );

   # Un-Webify plus signs and %-encoding
   $value =~ tr/+/ /;
   $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
   $value =~ s/<!--(.|\n)*-->//g;
   $value =~ s/<([^>]|\n)*>//g;

   $query{$name} = $value;
}

print "Content-type: text/html\n\n";
print "<HTML>\n";
print "<HEAD>\n";
print "<TITLE>Test Page</TITLE>\n";
print "</HEAD>\n";
print "<BODY>\n";
print "<H3>Hello</H3>\n";

print "<P>User = ".$ENV{REMOTE_USER}."</P>\n";
foreach my $key ( sort keys %query ) {
   print "$key = $query{$key}<BR>\n";
}
exit;


