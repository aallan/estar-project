#!/software/perl-5.8.8/bin/perl

  #use lib $ENV{"ESTAR_PERL5LIB"};     
  use lib "/work/estar/third_generation/lib/perl5";
  use eSTAR::Util;
  use eSTAR::Observation;
  use eSTAR::RTML::Parse;
  use eSTAR::RTML::Build;
  use XML::Document::RTML;
  
  #use Config::User;
  use File::Spec;
  use Time::localtime;
  use Data::Dumper;
  use Fcntl qw(:DEFAULT :flock);
  use DateTime;
  use DateTime::Format::ISO8601;
   
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
 
# M A I N   L O O P  #########################################################
  print "Content-type: text/ascii\n\n";  
  
  my $dir = File::Spec->catdir( File::Spec->rootdir(), "home", "estar", 
                                ".estar", "user_agent", "state" );
  $dir = File::Spec->catdir( $dir, $query{dir} ) if defined $query{dir};
  				
  my ( @files );
  if ( opendir (DIR, $dir )) {
     foreach ( readdir DIR ) {
  	push( @files, $_ ); 
     }
     closedir DIR;
  } else {
     error("Can not open state directory ($dir) for reading");      
  } 
  my @sorted = sort {-M "$dir/$a" <=> -M "$dir/$b"} @files;
  @files = @sorted;
  
  my $count = 0;	
  foreach my $i ( 0 ... $#files ) {
     
     #print "\n$i $files[$i] ";
     
     next if $files[$i] =~ m/\./;
     next if $files[$i] =~ m/\.\./;
     next if $files[$i] =~ m/^\d{4}$/;
     next if $files[$i] =~ m/^\d{2}-\d{4}$/;
   
     $count = $count + 1;
     #print " count = $count";

  }
  print $count;  
  
  exit;
  
# S U B - R O U T I N E S #################################################

 
  sub error {
    my $error = shift;
  
    print "Content-type: text/html\n\n";       
    print "Error: $error";
  }
