#!/usr/bin/perl

use Time::localtime;
use Net::Domain qw(hostname hostdomain);
use LWP::UserAgent;
use Data::Dumper;

my $count = "http://estar5.astro.ex.ac.uk/robonet-1.0/cgi-bin/count.cgi";
my $single = "http://estar5.astro.ex.ac.uk/robonet-1.0/cgi-bin/single.cgi";

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

# G R A B   N E T W O R K . S T A T U S   F I L E -------------------------

my $lwp = new LWP::UserAgent( timeout => 15 );
$lwp->env_proxy();
$lwp->agent( "eSTAR iPhone Robonet Script /$VERSION (". hostname() . ")" );
my $request = new HTTP::Request(GET => $count);
$request->authorization_basic('aa', 'wibble');
eval { $reply = $lwp->request( $request ) };
if ( $@ ) {
   error( "$@" );
   exit;
}   

# We successfully made a request but it returned bad status
unless ( ${$reply}{"_rc"} eq 200 ) {
  error( "(${$reply}{_rc}): ${$reply}{_msg}");
  exit;
}
my $total = ${$reply}{_content};
 
# we should have a reply
print "Content-type: text/html\n\n";

unless( defined $query{min} && defined $query{max} ) {
   print '<div title="Microlensing" class="panel">';
   print ' <fieldset>';

   if( $query{listby} eq "id" ) {
      print '<div class="row">';
      print '<a class="serviceButton" href="robonet/cgi-bin/status.cgi?listby=object">List by Object Name</a>';
      print '</div>';
   } else {
      print '<div class="row">';   
      print '<a class="serviceButton" href="robonet/cgi-bin/status.cgi?listby=id">List by Unique Identifier</a>';
      print '</div>';
   }
   print '</fieldset>';

   print '<fieldset>';
   print '<div class="row">';
   print '  <label>Total</label>';
   print '  <p>'.$total.'</p>';
   print '</div>';
   print '</fieldset>';
}
   
my $max = $query{max};
my $min = $query{min};
$max = 10 unless defined $max;
$max = $total if $max > $total;
$min = 0 unless defined $min;

print "<fieldset>";
foreach my $i ( $min ... $max ) {
   $request = new HTTP::Request(GET => $single . "?file=$i" );
   $request->authorization_basic('aa', 'wibble');
   eval { $reply = $lwp->request( $request ) };
   if ( $@ ) {
      ${$reply}{_content} = "Error";
   }   
   print '<div class="row">';
   print '  <label>'.$i.'</label>';
   print '  <p>'.$i.'</p>';
   print '</div>';
}
print "</fieldset>";

my $next_min = $max + 1;
my $next_max = $next_min + 10;
$next_max = $total if $next_max > $total;
if ( $next_max > $max ) {
   print "<fieldset>";   
   print '<div class="row">';
   print '  <a class="serviceButton" target="_replace" href="robonet/cgi-bin/status.cgi?min='.$next_min.'&max='.$next_max.'&listby='.$query{listby}.'">Get more objects...</a>';
   print '</div>';  
   print "</fieldset>";
}


unless( defined $query{min} && defined $query{max} ) {
   print "</div>";
}
exit;
