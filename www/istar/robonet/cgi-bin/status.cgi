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
$min = 1 unless defined $min;

print "<fieldset>";
foreach my $i ( $min ... $max ) {
   $request = new HTTP::Request(GET => $single . "?file=$i" );
   $request->authorization_basic('aa', 'wibble');
   eval { $reply = $lwp->request( $request ) };
   if ( $@ ) {
      ${$reply}{_content} = "Error";
   }   
   
   my @fields = split " ", ${$reply}{_content};
   my $node = $fields[11]; 
   $node = '<a href="estar/cgi-bin/status.cgi?item=LT">LT</a>' if $node eq "LT";
   $node = '<a href="estar/cgi-bin/status.cgi?item=FTN">FTN</a>' if $node eq "FTN";
   $node = '<a href="estar/cgi-bin/status.cgi?item=FTS">FTS</a>' if $node eq "FTS";

   print '<div class="row">';
   if ( $query{listby} eq "id" ) {
      my $id = $fields[0];
      my @split = split ":", $id;
      $id = $split[0];
      print '  <label>'.$id.'</label>';
   } else {
      my $target = $fields[1];
      print '  <label>'.$target.'</label>';
   }
   my $obs_status = $fields[12];
   my $observations = 0;
   if ( $obs_status =~ /\(/ ) {
      my ($status, $num) = split /\(/, $obs_status;
      $obs_status = $status;
      chop( $num );
      $observations = $num;
   }
   $obs_status = "Queued" if $obs_status eq "queued";
   $obs_status = "No Response" if $obs_status eq "no_response";
   $obs_status = "Failed" if $obs_status eq "failed";
   $obs_status = "Error" if $obs_status eq "error";
   $obs_status = "In Progress" if $obs_status eq "in_progress";
   $obs_status = "Expired" if $obs_status eq "expired";
   $obs_status = "Incomplete" if $obs_status eq "incomplete";
   $obs_status = "Returned" if $obs_status eq "returned";
   $obs_status = "Unknown" if $obs_status eq "unknown";
   $obs_status = $obs_status . " ($observations)" if $observations != 0;
   my $id = $fields[0];
   $id =~ s/#/%23/g;
   print '  <p><a href="robonet/cgi-bin/observation.cgi?id='.$id.'">'.$obs_status.'</a> on '.$node.'</p>';
   print '</div>';
   
}
print "</fieldset>";

my $next_min = $max + 1;
my $next_max = $next_min + 10;
$next_max = $total if $next_max > $total;
if ( $next_max > $max ) {
   print "<fieldset>";   
   print '<div class="row">';
   print '  <a class="_replaceButton" target="_replaceButton" href="robonet/cgi-bin/status.cgi?min='.$next_min.'&max='.$next_max.'&listby='.$query{listby}.'">Get more objects...</a>';
   print '</div>';  
   print "</fieldset>";
}


unless( defined $query{min} && defined $query{max} ) {
   print "</div>";
}
exit;
