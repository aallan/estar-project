#!/usr/bin/perl

use Time::localtime;

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

# B U I L D   F O R M ----------------------------------------------------------

my $user = $ENV{REMOTE_USER};

print "Content-type: text/html\n\n";

print '<form title="Cone Search" class="panel" action="cone/cgi-bin/submit.cgi" method="GET">';

print '<div>';
print '<label class="altLabel">R.A.:</label>';
print '<input class="altInput" name="RA" value="'.$query{ra}.'" />';
print '<br><i><small>Format: hh mm ss.s</small></i>';
print '</div>';

print '<div>';
print '<label class="altLabel">Dec.:</label>';
print '<input class="altInput" name="DEC" value="'.$query{dec}.'" />';
print '<br><i><small>Format: &plusmn;dd mm ss.s</small></i>';
print '</div>';

print '<div>';
print '<label class="altLabel">Radius:</label>';
print '<input class="altInput" name="SR" value="'.$query{sr}.'" />';
print '<br><i><small>Format: deg.</small></i>';
print '</div>';


print '<div>';
print '<select NAME="DB">';
print "<option VALUE='blanco1' style='color:#00FF00'> Blanco 1";
print "<option VALUE='n2547' style='color:#00FF00'> N2547";
print "<option VALUE='ic4665' style='color:#00FF00'> IC4665";
print "<option VALUE='m50' style='color:#00FF00'> M50";
print "<option VALUE='n2362' style='color:#00FF00'> N2362";
print "<option VALUE='n2516' style='color:#00FF00'> N2516";
print "<option VALUE='chiper' style='color:#00FF00'> Chi Per";
print "<option VALUE='hper' style='color:#00FF00'> H Per";
print "<option VALUE='m34' style='color:#00FF00'> M34";
print "<option VALUE='onc' style='color:#00FF00'> ONC";
print '</select>';
print '</div>';

print '<input TYPE="submit" VALUE="Submit">'."\n";

print '</form>';
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
