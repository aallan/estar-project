# -*-perl-*-

=head1 NAME

estar_trig - Send photometry results back to eSTAR embedded agent

=head1 DESCRIPTION

If the data are associated with a trigger from the eSTAR network,
this primitive sends the photometry results back to the user agent.
The results are tagged with the particular eSTAR trigger ID and
includes a catalogue of photometry results and the reduced group.

=cut

# Load these in the primitive rather than in the pipeline
# infrastructure since we do not want the shipped pipeline
# to have these dependencies.
require SOAP::Lite;
require Digest::MD5;
require URI;
require HTTP::Cookies;

# Hard-wired for the moment. Probably okay for now since we
# should be checking for UKIRT domain. Probably do not want the
# password in the shipped pipeline.
my $host = "estar.ukirt.jach.hawaii.edu";
my $port = 8080;
my $user = "agent";
my $password = "InterProcessCommunication";

# The embedded agent is responsible for copying this to a public
# location

# Hard wire the file and catalogue for testing
my $filename = "estar_test.fits";
my $catalogue = "estar_test.cat";
my $ESTAR_ID = '000001:UA:v1-6:run#1:user#aa';

# -----------------------------------------------------------------------
# Quick hack to send multiple messages on trigger, need both 'update' and
# 'observation' messages. Brad, read carefully before making further changes. 
# 
# -- AALLAN (21-JUL-03)
#
# Note that there are two types of alert the ORAC-DR pipeline should
# send to the eSTAR agent. An 'update' alert and an 'observation' alert.
# An update alert is currently ignored by the agent, but should come at
# the end of each observation frame, a 'observation' alert comes at the
# end of all processing pointing to the final data products. For now
# lets hardwire the sending of both alerts, after all we've just finished
# a frame, and then (since the observation currently only consists of
# a single frame) we need an update message to say that frame is done and
# then immediately an observation message to say the observation is
# done.
# ------------------------------------------------------------------------


my %hash = ( ID => $ESTAR_ID,
	     FITS => "http://www.jach.hawaii.edu/~timj/" . $filename,
	     Catalog => "http://www.jach.hawaii.edu/~timj/" . $catalogue,
	   );

my $endpoint = "http://" . $host . ":" . $port;
my $uri = new URI($endpoint);

# This is an inline version of Alasdair's make_cookie
# routine from ESTAR
my $cookie = $user . "::" . Digest::MD5::md5_hex( $password );
$cookie =~ s/(.)/sprintf("%%%02x", ord($1))/ge;
$cookie =~ s/%/%25/g;
# end make_cookie

# put the cookie in an object suitable for SOAP transport
my $cookie_jar = HTTP::Cookies->new();
$cookie_jar->set_cookie( 0, user => $cookie, '/', $uri->host(), $uri->port());

# we are now going to connect to the SOAP agent
my $soap = new SOAP::Lite();
my $urn = "urn:/node_agent";

$soap->uri($urn);
$soap->proxy( $endpoint, cookie_jar => $cookie_jar );

# UPDATE MESSAGE
# --------------

$hash{AlertType} = "update";

print( "Sending SOAP message:\n");
for my $key (sort keys %hash) {
  print "        $key: $hash{$key}\n";
}

my $result;
eval { $result = $soap->handle_data( %hash ) };
if( $@ ) {
  die "Unable to handle SOAP request: $@";
}

# The result of the SOAP request.
unless( $result->fault() ) {
  print "SOAP Result: " . $result->result() . "\n";
} else {
  warn "SOAP Fault Code: " . $result->faultcode() . "\n";
  die "SOAP Fault String: " . $result->faultstring() . "\n";

}

# OBSERVATION MESSAGE
# -------------------

$hash{AlertType} = "observation";

print( "Sending SOAP message:\n");
for my $key (sort keys %hash) {
  print "        $key: $hash{$key}\n";
}

eval { $result = $soap->handle_data( %hash ) };
if( $@ ) {
  die "Unable to handle SOAP request: $@";
}

# The result of the SOAP request.
unless( $result->fault() ) {
  print "SOAP Result: " . $result->result() . "\n";
} else {
  warn "SOAP Fault Code: " . $result->faultcode() . "\n";
  warn "SOAP Fault String: " . $result->faultstring() . "\n";
}

