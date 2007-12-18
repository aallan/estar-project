#!/Software/perl-5.8.8/bin/perl

my $dir = './tiles';

opendir(DIR, $dir);
my @zoom = readdir(DIR);
closedir DIR;

foreach my $z ( 0 ... $#zoom) {
   
   opendir(DIR, $dir . '/' . $zoom[$z]);
   my @files = readdir(DIR);
   closedir DIR;

   foreach my $i ( 0 ... $#files ) {
      if ( $files[$i] =~ "tile_"  ) {
      
         my $file = "$dir/$zoom[$z]/$files[$i]";
         #print $files[$i] . "\n";
         $files[$i] =~ m/tile_(\d+)_(\d+)_(\d+)\.jpg/;
         my $z = $1;
         my $x = $2;
         my $y = $3;
	 my $l = -s $file;

         #print "    $file   $z $x $y $l\n";
         system("./eatblob/eatblob MapTiles.sqlitedb $file \"insert into images (zoom, x, y, flags, length, data) values ($z, $x, $y, 2, $l, ?);\"");
      }	 
   }
   
}

exit;      
