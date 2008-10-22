#!/usr/bin/perl -X

use LWP::UserAgent;
use HTTP::Request;

print "Content-type: text/html\n\n";

my $submit = "http://estar8.astro.ex.ac.uk/monitor/public/cgi-bin/iphone_search.cgi";

# G E N E R A T E   O B S E R V A T I O N ------------------------------------

my $lwp = new LWP::UserAgent( timeout => 59 );
$lwp->env_proxy();
$lwp->agent( "eSTAR iPhone Submit Script at estar.org.uk" );
my $request = new HTTP::Request( GET => $submit . "?" . $ENV{QUERY_STRING} );
$request->authorization_basic('aa', 'wibble');

eval { $reply = $lwp->request( $request ) };
if ( $@ ) {
   error( "$@" );
   exit;
}   

{
 local ($oldbar) = $|;
 $cfh = select (STDOUT);
 $| = 1;
 print ${$reply}{_content};
 $| = $oldbar;
 select ($cfh);
}

exit;

# S U B - R O U T I N E S ----------------------------------------------------

sub error {
   my $string = shift;
   
   print '<div title="Error" class="panel">';
   print "<p>" . $string . "</p>";
   print "</div>";
} 


