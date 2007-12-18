#!/Software/perl-5.8.8/bin/perl

mkdir "tiles";
mkdir "tiles/0";
mkdir "tiles/1";
mkdir "tiles/2";
mkdir "tiles/3";
mkdir "tiles/4";
mkdir "tiles/5";
mkdir "tiles/6";

my $max;
foreach my $z ( 0 ... 6 ) {

   $max = 0 if $z == 0;
   $max = 1 if $z == 1;
   $max = 3 if $z == 2;
   $max = 7 if $z == 3;
   $max = 15 if $z == 4;
   $max = 31 if $z == 5;
   $max = 63 if $z == 6;
 
   for my $x ( 0 ... $max ) {
      for my $y ( 0 ... $max ) {
         my $url = 
	   "http://mw1.google.com/mw-planetary/sky/skytiles_v1/".$x."_".$y."_".$z.".jpg";
         my $file = "tiles/".$z."/tile_".$z."_".$x."_".$y.".jpg";
    
         system("wget -vO $file $url");
      }
   }
}
exit;
