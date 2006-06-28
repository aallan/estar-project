#!/software/perl-5.8.6/bin/perl

  #use lib $ENV{"ESTAR_PERL5LIB"};     
  use lib "/work/estar/third_generation/lib/perl5";
  use eSTAR::Observation;
  use eSTAR::RTML::Parse;
  use eSTAR::RTML::Build;
  
  #use Config::User;
  use File::Spec;
  use Time::localtime;
  use Data::Dumper;
  use Fcntl qw(:DEFAULT :flock);
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

# G R A B   F I L E S ---------------------------------------------------------

  my $header;
  unless ( open ( FILE, "<../header.inc") ) {
     error( "Can not open header.inc file", undef, \%query );
     exit;
  }
  {
     undef $/;
     $header = <FILE>;
     close FILE;
  }
  $header =~ s/PAGE_TITLE_STRING/GRB Observation Status/g;
  $header =~ s/<title>/<link rel="stylesheet" HREF="..\/css\/box.css" TYPE="text\/css"><title>/;

  my $footer;
  unless ( open ( FILE, "<../footer.inc") ) {
     error( "Can not open footer.inc file", undef, \%query );
     exit;
  }
  {
     undef $/;
     $footer = <FILE>;
     close FILE;
  }
  $footer =~ s/LAST_MODIFIED_DATE/ctime()/e;
 
# M A I N   L O O P  #########################################################
  
  my $dir = File::Spec->catdir( File::Spec->rootdir(), "home", "estar", 
                                ".estar", "user_agent", "state" );
				
  my ( @files );
  if ( opendir (DIR, $dir )) {
     foreach ( readdir DIR ) {
  	push( @files, $_ ); 
     }
     closedir DIR;
  } else {
     error("Can not open state directory ($dir) for reading");      
  } 
  #my @sorted = sort {-M "$dir$a" <=> -M "$dir$b"} @files;
  #@files = @sorted;

  # NB: first 2 entries in a directory listing are '.' and '..'
  print "Content-type: text/html\n\n"; 
  print $header;
  print "<SCRIPT SRC='../js/boxover.js'></SCRIPT>\n";
  
  print "<P>Observation status at <font color='red'>" . 
        timestamp() . "</font></P>";
  
  print "<font size='-2'><table border='0' width='95%'>\n"; 
  print "<tr><th align='left'>Target</th>".
	"<th align='left'>Type</th>".
        "<th align='left'>Date</th>".
        "<th align='left'>Template</th>".
	"<th align='left'>Node</th>".
	"<th align='left'>Status?</th></tr>\n";
	
#  foreach my $i ( 2 ... $#files ) {
   for ( my $i = $#files; $i >= 2; $i = $i - 1 ) {
   
     print "<tr>";
     #print "<td><font color='grey'>$files[$i]</font></td>";
     my $object;
     eval { $object = thaw( $dir, $files[$i] ); };
     
     # QUERY OBSERVATION OBJECT ------------------------------------------
     if ( $@ ) {
        print "<td><font color='grey'>$files[$i]</font></td>";
        print "<td colspan='5'><font color='red'>$@</font></td>\n";
     } else {
        #print "<td><font color='green'>OK</font></td>\n";
	
	my $status = $object->status();
	my $node = $object->node();
        my ($node_name, $score_reply) = $object->highest_score();
	$node = "FTN" if $node eq "estar3.astro.ex.ac.uk:8077";
	$node = "LT" if $node eq "estar3.astro.ex.ac.uk:8078";
	$node = "FTS" if $node eq "estar3.astro.ex.ac.uk:8079";  
        $node = "UKIRT" if $node eq "estar.ukirt.jach.hawaii.edu:8080";
        my $score;
        eval { $score = $score_reply->score() if defined $score_reply; };
        if ( $@ ) {
           error( "$@");
           exit;
        }
        $score = "undef" unless defined $score;
	
	my $obs;
	eval { $obs = $object->obs_request(); };
	if ( $@ ) {
	   error( "$@");
	   exit;
	}

        my ($target, $time, $type, $ident, $ra, $dec);
	if( defined $obs ) {
           $target = $obs->target();
	   $time = $obs->time();
	   $type = $obs->targettype();
           $ident = $obs->targetident();
           $ra = $obs->ra();
           $dec = $obs->dec();
        }
	
        # TARGET - 1 ---------------------------------------------------
        unless ( defined $ra && defined $dec ) {
           $target = "Unknown" unless defined $target;
           print "<td><font color='grey'>";
	   print "$target";
   	   print "</font></td>\n";
        } else {
           $ra =~ m/^(\d+\s\d+\s\d+\.\d{2})/;
           $ra_fixed = $1 if defined $1;
           print "<td><font color='grey'><table><tr><td>";
           print "$ra_fixed, ";
           print "</td><td>";
           print "$dec";
           print "</td></tr></table></font></td>\n";

        }

        # TARGET TYPE - 2 ----------------------------------------------
	
	print "<td>";
	print "<font color='grey'>$type</font>"; 
	print "</td>\n";   
	 
	# TIMESTAMP - 3 ------------------------------------------------
	
	my $date = $time;
	$date =~ s/T\d{2}:\d{2}:\d{2}$//;
	print "<td>";
        print "<font color='grey'>$date</font>";
        print "</td>\n";
	  
	# EXPOSURE - 4 -------------------------------------------------  
	$ident = "Initial" if $ident eq "InitialBurstFollowup";
        $ident = "Main" if $ident eq "BurstFollowup";
        print "<td><font color='grey'>";
        print "$ident";
	print "</font></td>\n";
	
	# NODE - 5 ---------------------------------------------------------
	
	print "<td>";
        print "<DIV TITLE='offsetx=[-75] cssbody=[popup_body] cssheader=[popup_header] header=[Best Score] body=[<table><tr><td><b>$node_name</b></td></tr><tr><td><b>Score:</b> $score</td></tr></table>]' >";
        print "<font color='grey'>$node</font>";
        print "</DIV>";
        print "</td>\n";
		
	# STATUS - 6 ---------------------------------------------------
	print "<td>";
	print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Unique ID] body=[".$files[$i]."]' >";
	if ( $status eq "running" ) {
	   my $status = expired( $time );
	   if ( $status == -1 || $status == 0 ) {
              print "<font color='grey'>Queued</font>";
	   } else {   
              print "<font color='orange'>No response</font>";
           }
	   
	} elsif ( $status eq "failed" ) {
           print "<font color='red'>Failed</font>";
	   
	} elsif ( $status eq "update" ) {
           my @updates = $object->update();
           my $num = scalar @updates;
           print "<font color='green'>In progress";
           print " ($num)" if $num > 0;
           print "</font>";

	} elsif ( $status eq "incomplete" ) {
           my @updates = $object->update();
           my $num = scalar @updates;
           print "<font color='blue'>Incomplete";
           print " ($num)" if $num > 0;
           print "</font>";

	} elsif ( $status eq "returned" ) {
           my @updates = $object->update();
           my $num = scalar @updates;
           print "<font color='green'>Returned";
           print " ($num)" if $num > 0;
           print "</font>";

	} else {
           print "<font color='grey'>$status</font>";
	}
	print "</DIV></td>\n";
	
     }
     print "</tr>\n";
  }
  print "</table></font>\n";		
  print $footer;
  
  
  exit;
  
# S U B - R O U T I N E S #################################################
  
  sub error {
    my $error = shift;
  
    print "Content-type: text/html\n\n";       
    print "<HTML><HEAD>Error</HEAD><BODY>\n";
    print "<FONT COLOR='red'>Error: $error</FONT>\n";
    print "</BODY></HTML>";
  }
  
  sub thaw {
    my $state_dir = shift;
    my $id = shift;

    my $object;
   
    # check we actually have an $id
    return undef unless defined $id;
   
    # DE-SERIALISE OBJECT
    # ===================
    my $observation_object;
    my $file = File::Spec->catfile( $state_dir, $id );
    
    unless ( open ( SERIAL, "<$file" ) ) {
       die "Unique ID not in state directory";
    } else {
       unless ( flock( SERIAL, LOCK_EX ) ) {
         die "Unable to acquire exclusive lock: $!";
       }
      
       # deserialise the object  
       undef $/;
       my $string = <SERIAL>;
       close (SERIAL);
       $object = eval $string;
    }    
    return $object;
  }


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
  
  sub expired {
     my $end = shift;
     my $current = timestamp();
   
     chop $end if $end =~ /.\d{4}$/;
     chop $end if $end =~ /.\d{3}$/;
     #$current =~ s/.\d{4}$//;
   
     my $iso8601 = DateTime::Format::ISO8601->new;
     my $end_dt = $iso8601->parse_datetime( $end );
     $end_dt->add( days => 1 );
     
     my $current_dt = $iso8601->parse_datetime( $current );
     my $interval = DateTime->compare($current_dt, $end_dt);
     
     return $interval;

  }
