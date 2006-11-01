#!/software/perl-5.8.6/bin/perl

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

# G R A B   F I L E S ---------------------------------------------------------

my $inc;
unless ( open ( FILE, "<../events/sdss.inc") ) {
   print "Content-type: text/html\n\n";
   error( 'Can not open sdss.inc file' );
   exit;
}
{
   undef $/;
   $inc = <FILE>;
   close FILE;
}

my $header;
unless ( open ( FILE, "<../header.inc") ) {
   print "Content-type: text/html\n\n";       
   error( 'Can not open header.inc file' );
   exit;	
}
{
   undef $/;
   $header = <FILE>;
   close FILE;
}
$header =~ s/PAGE_TITLE_STRING/SDSS Message Timeline/g;
$header =~ s/<title>/<script src="..\/timeline\/timeline-api.js" type="text\/javascript"><\/script><title>/;
$header =~ s/validate.js/timeline-load.js/;

$header =~ s/CALLING_JAVASCRIPT/onload="onLoad();" onresize="onResize();"/;

my $footer;
unless ( open ( FILE, "<../footer.inc") ) {
   print "Content-type: text/html\n\n";       
   error( 'Can not open footer.inc file' );
   exit;	
}
{
   undef $/;
   $footer = <FILE>;
   close FILE;
}
$footer =~ s/LAST_MODIFIED_DATE/ctime()/e;
$footer =~ s/ABOUT_THIS_PAGE/Timeline is copyright &copy; <a href="http:\/\/simile.mit.edu\/timeline\/">SIMILE<\/a><\/P>/;

# G E N E R A T E   P A G E ------===--------------------------------------


print "Content-type: text/html\n\n";
print $header;

print '<div id="event_timeline" style="font-size: x-small; text-align: left; height: 150px; border=1px solid #aaa;"></div>';
print '<p align="justify"><font size="-2" color="grey">The <a href="http://simile.mit.edu/timeline/">Timeline Interface</a> is an HTML-based AJAX widget for visualizing time-based events and is copyright the <a href="http://simile.mit.edu/">SIMILE</a> project.</font></p>';

print 'The <a href="http://www.estar.org.uk/wiki/index.php/SDSS">SDSS</a> event time line is shown above, there are two independently scrollable bars (the upper in days, the lower in months), which can be panned by clicking and dragging to show previous events. The currently visible view in the upper scrollable area is represented by a light grey box on the lower area. Each <a href="http://www.estar.org.uk/wiki/index.php/SDSS">SDSS</a> event is represented by a marker, labelled with the event name, and clicking on the marker will bring up additional data and links for that event.';

print '<h3>Event List</h3>';
print '<P><a href="http://www.estar.org.uk/wiki/index.php/SDSS">SDSS</a> event messages are also available via an <a href="http://www.estar.org.uk/voevent/Caltech/Caltech.rdf" class="external text" title="http://www.estar.org.uk/voevent/Caltech/Caltech.rdf" rel="nofollow">RSS event feed</a> <span class="plainlinks"><a href="http://www.estar.org.uk/voevent/Caltech/Caltech.rdf" class="external text" title="http://www.estar.org.uk/voevent/Caltech/Caltech.rdf" rel="nofollow"><img src="http://www.estar.org.uk/wiki/uploads/8/8b/Xml-button.jpg" alt="Xml-button.jpg" /></a><span> <span class="plainlinks"><a href="http://www.estar.org.uk/voevent/Caltech/Caltech.rdf" class="external text" title="http://www.estar.org.uk/voevent/Caltech/Caltech.rdf" rel="nofollow"><img src="http://www.estar.org.uk/wiki/uploads/0/09/Rss.png" alt="Rss.png" /></a><span></P>';
print $inc;

print $footer;

exit;

sub timestamp {
   # ISO format 2006-01-05T08:00:00
   		     
   my $year = 1900 + localtime->year();
   
   my $month = localtime->mon() + 1;
   $month = "0$month" if $month < 10;
   
   my $day = localtime->mday();
   $day = "0$day" if $day < 10;
   
   my $hour = localtime->hour();
   $hour = "0$hour" if $hour < 10;
   
   my $min = localtime->min();
   $min = "0$min" if $min < 10;
   
   my $sec = localtime->sec();
   $sec = "0$sec" if $sec < 10;
   
   my $timestamp = $year ."-". $month ."-". $day ."T". 
   		   $hour .":". $min .":". $sec;

   return $timestamp;
}   

sub error {
  my $error = shift;
  my $query = shift;
  
  print "Content-type: text/html\n\n";       
  print "<HTML><HEAD>Error</HEAD><BODY><FONT COLOR='red'>".
        "Error: $error</FONT><BR><BR>";
  if ( defined $query ) {
     print "<P><PRE>" . Dumper( $query ). "</PRE></P>";
  }
  print "</BODY></HTML>";
}

