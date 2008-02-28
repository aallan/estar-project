#!/software/perl-5.8.8/bin/perl

use Time::localtime;
use Data::Dumper;
use Config::Simple;

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

my $valid = 0;
if ( $query{fieldID} eq "description" ) {
   $valid = 1;

} elsif ( $query{fieldID} eq "previous_ivorn" ) {
   $valid = 1 if $query{inputValue} =~ "ivo://";
   $valid = 1 if $query{inputValue} eq "";

} elsif ( $query{fieldID} eq "contact_name" ) {
   $valid = 1 if $query{inputValue} =~ m/\w+\s\w/;
   $valid = 1 if $query{inputValue} eq "";

} elsif ( $query{fieldID} eq "contact_email" ) {
   $valid = 1 if $query{inputValue} =~ m/\w+@\w+/;
   $valid = 1 if $query{inputValue} eq "";

} elsif ( $query{fieldID} eq "contact_phone" ) {
   $valid = 1 if $query{inputValue} =~ m/\+\d{2}-\d{4}-\d{6}/;
   $valid = 1 if $query{inputValue} =~ m/\+\d{1}-\d{3}-\d{3}-\d{4}/;
   $valid = 1 if $query{inputValue} eq "";

} elsif ( $query{fieldID} eq "short_name" ) {
   #if ( $query{inputValue} eq "RAPTOR" ||
   #     $query{inputValue} eq "eSTAR" ) {
   #   $valid = 1;
   #}	
   #$valid = 1 if $query{inputValue} eq "";
   $valid = 1;

} elsif ( $query{fieldID} eq "facility" ) {
   #if ( $query{inputValue} eq "Robonet-1.0" ||
   #     $query{inputValue} eq "TALONS" ) {
   #   $valid = 1;
   #}
   #$valid = 1 if $query{inputValue} eq "";
   $valid = 1;

} elsif ( $query{fieldID} eq "how_reference" ) {
   $valid = 1 if $query{inputValue} =~ "http://";
   $valid = 1 if $query{inputValue} eq "";

} elsif ( $query{fieldID} eq "ra" ) {
   $query{inputValue} =~ s/:/ /g;
   $valid = 1 if $query{inputValue} =~ m/^\d{2}\s\d{2}\s\d{2}\.\d{1}$/;
   $valid = 1 if $query{inputValue} =~ m/^\d{2}\s\d{2}\s\d{2}$/;
   $valid = 1 if $query{inputValue} eq "";

} elsif ( $query{fieldID} eq "dec" ) {
   $query{inputValue} =~ s/:/ /g;
   $valid = 1 if $query{inputValue} =~ m/^\d{2}\s\d{2}\s\d{2}\.\d{1}$/;
   $valid = 1 if $query{inputValue} =~ m/^\d{2}\s\d{2}\s\d{2}$/;
   $valid = 1 if $query{inputValue} =~ m/^\+\d{2}\s\d{2}\s\d{2}\.\d{1}$/;
   $valid = 1 if $query{inputValue} =~ m/^\+\d{2}\s\d{2}\s\d{2}$/;
   $valid = 1 if $query{inputValue} =~ m/^-\d{2}\s\d{2}\s\d{2}\.\d{1}$/;
   $valid = 1 if $query{inputValue} =~ m/^-\d{2}\s\d{2}\s\d{2}$/;
   $valid = 1 if $query{inputValue} eq "";

} elsif ( $query{fieldID} eq "time" ) {
   $valid = 1 if $query{inputValue} =~ m/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/;
   $valid = 1 if $query{inputValue} eq "";

} else {
   $query{fieldID} = "description";
   $valid = 1;
}

my $response = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'.
           '<response>'.
           '<result>'.
           $valid.
           '</result>'.
           '<fieldid>'.
           $query{fieldID}.
           '</fieldid>'.
           '</response>';

print "Content-Type: text/xml\n\n";
print $response;

exit;
