#!/software/perl-5.8.8/bin/perl

use Time::localtime;
use Data::Dumper;
use Astro::VO::VOEvent;
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use URI;
use HTTP::Cookies;

print "Content-type: text/html\n\n";

my $event_host = "estar6.astro.ex.ac.uk";
my $event_port = "9099";

my $agent_host = "estar5.astro.ex.ac.uk";
my $agent_port = "8000";

# create a user/passwd cookie
my $cookie = make_cookie( "agent", "InterProcessCommunication" );

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

# G E N E R A T E   O B S E R V A T I O N ------------------------------------

my %observation;

if ( $query{set_toop} == 1 ) {
   $observation{toop} = "toop";
} else {
   $observation{toop} = "normal";
}

$observation{user} = "kdh1";
$observation{pass} = "EXOfollowup";
$observation{project} = "exoplanet";
$observation{ra} = $query{ra};
$observation{dec} = $query{dec};
$observation{target} = $query{object_name};
$observation{exposure} = $query{exposure},
$observation{passband} = "R";
$observation{type} = "ExoPlanetMonitor";
$observation{groupcount} = $query{group_count};
$observation{starttime} = $query{start_time};
$observation{endtime} = $query{end_time};

# hack, don't know where the space comes from
$observation{starttime} =~ s/ /\+/;   
$observation{endtime} =~ s/ /\+/;   

$observation{toop} = $query{type} unless defined $observation{toop};
$observation{filter} = $query{filter};
$observation{priority} = 0;

if( $observation{toop} eq "toop" ) {
  $observation{seriescount} = undef;
  $observation{interval} = undef;
  $observation{tolerance} = undef;
} else { 
  $observation{seriescount} = $query{series_count} if $query{series_count} ne "";
  $observation{interval} = "PT" . $query{interval} . "S" if $query{interval} ne "";
  $observation{tolerance} = "PT" . $query{tolerance} . "S" if  $query{tolerance} ne "";
}

# O B S E R V I N G   R E Q U E S T -------------------------------------------- 

# end point
my $agent_endpoint = "http://" . $agent_host . ":" . $agent_port;
my $agent_uri = new URI($agent_endpoint);

my $agent_cookie_jar = HTTP::Cookies->new();
$agent_cookie_jar->set_cookie(0, user => $cookie, '/', $agent_uri->host(), $agent_uri->port());

# create SOAP connection
my $agent_soap = new SOAP::Lite();

$agent_soap->uri( "urn:/user_agent" ); 
$agent_soap->proxy($agent_endpoint, cookie_jar => $agent_cookie_jar );
    
# grab result 
my $obs_result;
if ( $query{"all_telescopes"} == 1 ) {
   eval { $obs_result = $agent_soap->all_telescopes( %observation ); };
} else {
   eval { $obs_result = $agent_soap->new_observation( %observation ); };
}
if ( $@ ) {
   my $error = "$@";
   error( $error );
   exit;   
}

my $obs_return = $obs_result->result(); 

# G E N E R A T E   P A G E --------------------------------------------------

print '<div title="Submitted" class="panel">';

print "<H2>Transport Status</H2>";
 
print "<fieldset>";
print '<div class="row">';
print "<label>Transport</label>";
if ( $agent_soap->transport()->status() =~ "200" ) {
   print '<p id="green">' . $agent_soap->transport()->status() . "</p>";
} else {
   print '<p id="red">' . $agent_soap->transport()->status() . "</p>";
}
print "</div>";
if ($obs_result->fault() ) {
  print '<div class="row">';
  print "<label>Fault</label>";
  print "<p>" . $obs_result->faultcode() . "</p>";
  print "</div>";
#  print "<div>";
#  print "<p>" . $obs_result->faultstring() . "</p>";
#  print "</div>"; 
  print "</fieldset>";
  exit;
}
print "</fieldset>";

print "<H2>Queued Status</H2>";

$obs_return =~ s/>/&gt;/g;
$obs_return =~ s/</&lt;/g;

print "<fieldset>";
my %telescopes;
if ( $obs_return =~ "OK" ) {
   $obs_return =~ m/\[(.+)\]/;
   my @tels = split " ", $1;

   foreach my $i ( 0 ... $#tels ) {
      $telescopes{$tels[$i]} = 1;
   }   
} 
   
print '<div class="row">';
print "<label>LT</label>";
if ( $telescopes{LT} ) {
   print '<p id="green">OK</p>';
} else {   
   print '<p id="red">NO</p>';
}   
print "</div>"; 

print '<div class="row">';
print "<label>FTN</label>";
if ( $telescopes{FTN} ) {
   print '<p id="green">OK</p>';
} else {   
   print '<p id="red">NO</p>';
}   
print "</div>"; 

print '<div class="row">';
print "<label>FTS</label>";
if ( $telescopes{FTS} ) {
   print '<p id="green">OK</p>';
} else {   
   print '<p id="red">NO</p>';
}   
print "</div>";   
  
  
print "</fieldset>";

print '</div>';
   
exit;

# S U B - R O U T I N E S ----------------------------------------------------

sub make_cookie {
   my ($user, $passwd) = @_;
   my $cookie = $user . "::" . md5_hex($passwd);
   $cookie =~ s/(.)/sprintf("%%%02x", ord($1))/ge;
   $cookie =~ s/%/%25/g;
   $cookie;
}

sub error {
   my $string = shift;
   print $string;
}   
