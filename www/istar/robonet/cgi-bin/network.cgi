#!/usr/bin/perl

use Time::localtime;
use Net::Domain qw(hostname hostdomain);
use LWP::UserAgent;
use Data::Dumper;

my %OPTS = @LWP::Protocol::http::EXTRA_SOCK_OPTS;
$OPTS{MaxLineLength} = 8192; # Or however large is needed...
@LWP::Protocol::http::EXTRA_SOCK_OPTS = %OPTS;

my $single = "http://estar5.astro.ex.ac.uk/robonet-1.0/cgi-bin/graphs.cgi";

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

# G R A B    I N F O    F I L E -------------------------

my $lwp = new LWP::UserAgent( timeout => 45 );
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
my @lines = split "\n", $line;


# M E N U --------------------------------------------------------------------

# we should have a reply
print "Content-type: text/html\n\n";

if ( !defined $query{tel} ) {

my @lt = split ",", $lines[0];
my @ftn = split ",", $lines[2];
my @fts = split ",", $lines[4];

my $queued = $lt[1] + $ftn[1] + $fts[1];
my $returned = $lt[2] + $ftn[2] + $fts[2];
my $incomplete = $lt[3] + $ftn[3] + $fts[3];
my $expired = $lt[4] + $ftn[4] + $fts[4];
my $failed = $lt[5] + $ftn[5] + $fts[5];
my $no_reply = $lt[6] + $ftn[6] + $fts[6];

  my $url_head = 'http://chart.apis.google.com/chart?cht=p&chco=0000ff&chd=t:';  
  my $url_foot = '&chs=360x200&chl=Queued|Returned|Incomplete|Expired|Failed|No%20Response';

print '<ul title="Performance">';
print "   <li><img src='$url_head$queued,$returned,$incomplete,$expired,$failed,$no_reply$url_foot'></li>";
print '   <li><a href="robonet/cgi-bin/network.cgi?tel=LT">LT</a></li>';
print '   <li><a href="robonet/cgi-bin/network.cgi?tel=FTN">FTN</a></li>';
print '   <li><a href="robonet/cgi-bin/network.cgi?tel=FTS">FTS</a></li>';
print '</ul>';

} elsif ( $query{tel} eq "LT" ) {

print '<div title="Performance" class="panel">';
print ' <H2>Liverpool Telescope</H2>';
print '<div><img src="'.$lines[1].'"></div>';
print ' <fieldset>';
my @num = split ",", $lines[0];
print '<div class="row">';
print '<label>Total</label>';
print '<p>'.$num[0].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="green">Queued</label>';
print '<p id="green">'.$num[1].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="green">Returned</label>';
print '<p id="green">'.$num[2].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="orange">Incomplete</label>';
print '<p id="orange">'.$num[3].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="orange">Expired</label>';
print '<p id="orange">'.$num[4].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="red">Failed</label>';
print '<p id="red">'.$num[5].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="red">No Reply</label>';
print '<p id="red">'.$num[6].'</p>';
print '</div>';
print '</fieldset>';
print '</div>';

} elsif ( $query{tel} eq "FTN" ) {

print '<div title="Performance" class="panel">';
print ' <H2>Faulkes North</H2>';
print '<div><img src="'.$lines[3].'"></div>';
print ' <fieldset>';
@num = split ",", $lines[2];
print '<div class="row">';
print '<label>Total</label>';
print '<p>'.$num[0].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="green">Queued</label>';
print '<p id="green">'.$num[1].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="green">Returned</label>';
print '<p id="green">'.$num[2].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="orange">Incomplete</label>';
print '<p id="orange">'.$num[3].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="orange">Expired</label>';
print '<p id="orange">'.$num[4].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="red">Failed</label>';
print '<p id="red">'.$num[5].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="red">No Reply</label>';
print '<p id="red">'.$num[6].'</p>';
print '</div>';
print '</fieldset>';
print '</div>';

} elsif ( $query{tel} eq "FTS" ) {

print '<div title="Performance" class="panel">';
print ' <H2>Faulkes South</H2>';
print '<div><img src="'.$lines[5].'"></div>';
print ' <fieldset>';
@num = split ",", $lines[4];
print '<div class="row">';
print '<label>Total</label>';
print '<p>'.$num[0].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="green">Queued</label>';
print '<p id="green">'.$num[1].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="green">Returned</label>';
print '<p id="green">'.$num[2].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="orange">Incomplete</label>';
print '<p id="orange">'.$num[3].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="orange">Expired</label>';
print '<p id="orange">'.$num[4].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="red">Failed</label>';
print '<p id="red">'.$num[5].'</p>';
print '</div>';
print '<div class="row">';
print '<label id="red">No Reply</label>';
print '<p id="red">'.$num[6].'</p>';
print '</div>';
print '</fieldset>';
print '</div>';

}


exit;

sub error {
   my $string = shift;
   
   print "Content-type: text/html\n\n";
   print "<div title='Error' class='panel'>";
   print "<p>" . $string . "</p>";
   print "</div>";
}   
