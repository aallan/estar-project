#!/usr/bin/perl

use Time::localtime;
use Net::Domain qw(hostname hostdomain);
use LWP::UserAgent;
use Data::Dumper;

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

$query{id} =~ s/#/%23/g;
$single = $single . "?id=$query{id}";

# G R A B    I N F O    F I L E -------------------------

my $lwp = new LWP::UserAgent( timeout => 15 );
$lwp->env_proxy();
$lwp->agent( "eSTAR iPhone Robonet Script /$VERSION (". hostname() . ")" );
my $request = new HTTP::Request(GET => $single);
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
my $line = ${$reply}{_content};
my @fields = split " ", $line;
 
# we should have a reply
print "Content-type: text/html\n\n";


my $target = $fields[1];
print '<div title="'.$target.'" class="panel">';
print ' <fieldset>';

my $id = $fields[0];
my @split = split ":", $id;
$id = $split[0];
print '<div class="row">';
print '<label>ID</label>';
print '<p>'.$id.'</p>';
print '</div>';

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
print '<div class="row">';
print '<label>Status</label>';
print '<p>'.$obs_status.'</p>';
print '</div>';  

my $type = $fields[3];
print '<div class="row">'; 
print '<label>Type</label>';
print '<p>'.$type.'</p>';
print '</div>';

my $priority = $fields[4];
$priority = "Quite Urgent" if $priority == 0;
$priority = "High" if $priority == 1;
$priority = "Medium" if $priority == 2;
$priority = "Normal" if $priority > 2;
print '<div class="row">';
print '<label>Priority</label>';
print '<p>'.$priority.'</p>';
print '</div>';

my $starttime = $fields[5];
my $endtime = $fields[6];
print '<div class="row">'; 
print '<label>Start</label>';
print '<p>'.$starttime.'</p>';
print '</div>';
print '<div class="row">'; 
print '<label>End</label>';
print '<p>'.$endtime.'</p>';
print '</div>';

my $series_count = $fields[7];
my $group_count = $fields[8];
my $exposure = $fields[9];
my $exposure_string;
if ( $series_count != 0 && $group_count != 0 ) {
   $exposure_string = "$series_count&times;($group_count&times;$exposure)";
} elsif ( $series_count != 0 && $group_count == 0 ) {
   $exposure_string = "$series_count&times;(1&times;$exposure)";
} elsif ( $series_count  == 0 && $group_count != 0 ) {
   $exposure_string = "1&times;($group_count&times;$exposure)";
} elsif ( $series_count == 0 && $group_count == 0 ) {
   $exposure_string = "$exposure";
}
print '<div class="row">'; 
print '<label>Exposures</label>';
print '<p>'.$exposure_string.' sec</p>';
print '</div>';

my $filter = $fields[10];
print '<div class="row">'; 
print '<label>Filter</label>';
print '<p>'.$filter.'</p>';
print '</div>'; 

my $node = $fields[11]; 
$node = '<a href="estar/cgi-bin/status.cgi?item=LT">LT</a>' if $node eq "LT";
$node = '<a href="estar/cgi-bin/status.cgi?item=FTN">FTN</a>' if $node eq "FTN";
$node = '<a href="estar/cgi-bin/status.cgi?item=FTS">FTS</a>' if $node eq "FTS";
print '<div class="row">'; 
print '<label>Node</label>';
print '<p>'.$node.'</p>';
print '</div>'; 

my $project = $fields[13];
print '<div class="row">'; 
print '<label>Project</label>';
print '<p>'.$project.'</p>';
print '</div>'; 
  
print '</fieldset>';
print '</div>'; 



exit;
