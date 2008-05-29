#!/usr/bin/perl

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

print '<div title="Results" class="panel">';

print '<fieldset>';
foreach my $key ( sort keys %query ) {
   print '<div class="row">';
   print '<label>'.$key.'</label>';
   print '<p>'.$query{$key}.'</p>';
   print '</div>';
}
print '</fieldset>';
print '</div>';
 
exit;
