#!/software/perl-5.8.8/bin/perl

  #use lib $ENV{"ESTAR_PERL5LIB"};     
  use lib "/work/estar/third_generation/lib/perl5";
  use Astro::VO::VOEvent;
 
  use File::Spec;
  use Time::localtime;
  use Data::Dumper;
  use Fcntl qw(:DEFAULT :flock);
  use DateTime::Format::ISO8601;


# M A I N   L O O P  #########################################################
  
  my $dir = File::Spec->catdir( File::Spec->rootdir(), "home", "estar", 
                                ".estar", "event_broker", "state",
                                "Caltech", "nvo.caltech", "VOEvent" );

  my ( @files );
  if ( opendir (DIR, $dir )) {
     foreach ( readdir DIR ) {
        push( @files, $_ ); 
     }
     closedir DIR;
  } else {
     error("Can not open state directory ($dir) for reading");      
  } 

  my $xml = '<data>'."\n";
  my $widget = $xml;
  my $html = "<font size='-2'><table border='0' width='95%'><tr>\n";
  $html = $html . "<th align='left'>Candidate</th>";
  $html = $html . "<th align='left'>Message ID</th>";
  $html = $html . "<th align='left'>Time</th>";
  $html = $html . "<th align='left'>R.A.</th>";
  $html = $html . "<th align='left'>Dec.</th>";
  $html = $html . "</tr>";
   
  for ( my $i = $#files; $i >= 3; $i = $i - 1 ) {
     print "File $i of $#files\n";
     
     my $file = File::Spec->catfile( $dir, $files[$i] );
     my $document = new Astro::VO::VOEvent( File => $file );
     my $stamp = $document->time();
     print "$stamp\n\n";
     
     next unless $document->role() eq "observation";    

     $stamp =~ s/\+\d{4}$//;
     my $time;
     eval{ $time = DateTime::Format::ISO8601->parse_datetime( $stamp ); };
     if ( $@ ) {
       print "Error: $@\n";
       next;
     }  
     
     my $timestamp = $time->month_abbr() . " " . $time->day() . " " .
                     $time->year() . " " . $time->hms() . " GMT";
     
     my $name = $document->id();
     my @id = split "#", $name;
          
     # event page
      my $message =
         "http://www.estar.org.uk/voevent/Caltech/nvo.caltech/VOEvent/" .
         $id[1] . ".xml";

     
     my $event = '<event start="' . $timestamp . '" title="' . $id[1] . '" >';
     my $widget_event = $event;
 
     # start of content
     
     my $ra = $document->ra();
     my $dec = $document->dec();
     
     $ra = sprintf( "%.3f", $ra );
     $dec = sprintf( "%.3f", $dec );
     
     
     my %what = $document->what();
     #print Dumper( %what ) . "\n\n";
     
     my $content = "&lt;P align='left'&gt;R.A. $ra, ";
     $content = $content . "Dec. $dec&lt;/p&gt;";
     $content = $content . "&lt;ul align='left'&gt;"; 
     $content = $content . "&lt;li&gt;"; 
     $content = $content . "&lt;a href='$message'&gt;VOEvent Message&lt;/a&gt;"; 
     $content = $content . "&lt;/li&gt;";
     $content = $content . "&lt;li&gt;"; 
     $content = $content . "&lt;a href='".
                           $what{Reference}{uri}."'&gt;Event Data&lt;/a&gt;"; 
     $content = $content . "&lt;/li&gt;";
          
     my $line = "<tr>";

     $line = $line . "<td><font color='grey'>";
     $line = $line . $what{Reference}{name}. "</font></td>";
     
     $line = $line . "<td><font color='grey'>";
     $line = $line . "<a href='$message'>";
     $line = $line . $id[1] . "</a></font></td>";
     
     $line = $line . "<td><font color='grey'>";
     $line = $line . $stamp . "</font></td>";
          
     $line = $line . "<td><font color='grey'>";
     $line = $line . $ra . "</font></td>";

     $line = $line . "<td><font color='grey'>";
     $line = $line . $dec . "</font></td>";

     $line = $line . "</tr>\n";
     
     # end of content
     
     $event = $event . $content . '</event>' . "\n";

     # widget version
     my $widget_content = $content;
     $widget_content =~ s/href='/href='javascript:void\(0\)' onclick='clicked\("/g;
     $widget_content =~ s/.jpg'/.jpg");'/g;
     $widget_content =~ s/.dat'/.dat");'/g;
     $widget_content =~ s/.html'/.html");'/g;
     $widget_content =~ s/.xml'/.xml");'/g;

     $widget_event = $widget_event . $widget_content . '</event>' . "\n";
     
     
     $widget = $widget . $widget_event;
     $html = $html . $line . "\n";
     $xml = $xml . $event;
                  
  }
  $xml = $xml . '</data>';
  $widget = $widget . '</data>';
  $html = $html . '</table></font>';
  print "$widget";
  
  # output xml
  my $output = File::Spec->catfile(  File::Spec->rootdir(), "var", "www",
                                     "sdss", "events", "sdss.xml" );
				     
  unless ( open FILE, "+>$output" ) {
     print "Error: Can not open $output for updating\n";
     exit;
  }
  
  print FILE $xml;
  close ($output );

  # output widget xml
  my $output3 = File::Spec->catfile(  File::Spec->rootdir(), "var", "www",
                                  "sdss", "events", "sdssWidget.xml" );

  unless ( open FILE, "+>$output3" ) {     
     print "Error: Can not open $output3 for updating\n";
     exit;
  }
  print FILE $widget;
  close ( $output3 );
  
  # output html 
  my $output2 = File::Spec->catfile(  File::Spec->rootdir(), "var", "www",
                                     "sdss", "events", "sdss.inc" );
				     
  unless ( open FILE, "+>$output2" ) {
     print "Error: Can not open $output2 for updating\n";
     exit;
  }
  
  print FILE $html;
  close ( $output2 );
  
  exit;
