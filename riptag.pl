#!/usr/bin/perl -w

use lib qw(.);
use CDDB_get2 qw( get_cddb get_discids );
#use CDDB_get;
#use Env;
use Getopt::Long;
use String::ShellQuote;

### BEGIN VARIABLE DEFINITIONS
my (
      $VERSION,             # riptag version number.
      $version_opt,         # getopt version argument variable
      $cddev,               # getopt cd device name replacement

      $user_input,          # user input confirmation

      $num,                 # loop counter

      @tracks,              # array of tracks from Net:CDDB
      $artist,              # artist or group name
      $title,               # CD title
      $track,               # individual track name
      $disc_id,             # CD catalog number
      $num_tracks,          # number of tracks on CD
      $cat,                 # CD music genre
      $year,                # hacked into CDDB_get

      %cd,                  # info on the current disc

      $cddb_dir,            # Local CDDB directory

      $id3ren_path,         # full path to id3ren
      $lame_path,           # full path to lame
      $cdparanoia_path,     # full path to cdparanoia
   );
#### END VARIABLE DEFINITIONS

my $fixname;
sub fixname {
   $name = shift;
   $name2 = $name;

   $name2 =~ s/\[/\-/g;
   $name2 =~ s/\]//g;
   $name2 =~ s/://g;
   $name2 =~ s/: +/-/g;
   $name2 =~ s/\//-/g;
   $name2 =~ s/\) \(/-/g;
   $name2 =~ s/\) //g;
   $name2 =~ s/ \(/-/g;
   $name2 =~ s/\(//g;
   $name2 =~ s/12"/12\.inch/g;
   $name2 =~ s/7"/7\.inch/g;
   $name2 =~ s/["',!\?\)]+//g;
   $name2 =~ s/["',!\?\)¿¡]+//g;
   $name2 =~ s/&+/and/g;
   $name2 =~ s/%/percent/g;
   $name2 =~ s/\++/and/g;
   $name2 =~ s/ - /-/g;
   $name2 =~ tr/A-Z /a-z./;
   $name2 =~ s/^\.+//;
   $name2 =~ s/\.\.+/\./g;
   $name2 =~ s/-\./\-/g;
   $name2 =~ s/\.\-/\-/g;
   $name2 =~ s/\*/\-/g;
   $name2 =~ s/\-\./\./g;
#   $name2 =~ s/\\n//g;

   return($name2);
}

$cddev           = "/dev/cdrom";
$cddb_dir        = "$ENV{'HOME'}/.cddb";
$id3ren_path     = "/home/rburdick/tmp/rip/id3ren";
$lame_path       = "/usr/bin/lame";
$cdparanoia_path = "/usr/bin/cdparanoia";

# Please don't change this when sending patches.
$VERSION="0.0.3 (23 Feb 2002)";

GetOptions( "version"         => \$version_opt,
            "device=s"        => \$cddev,
            "cddbdir=s"       => \$cddb_dir
          );

if ($version_opt) {
   print "Version $VERSION\n";
   exit;
}

if (! -e $id3ren_path)
{
   print "\nWARNING: can't find id3ren at $id3ren_path!\n";
}

if (! -e $lame_path)
{
   print "\nWARNING: can't find lame at $lame_path!\n";
}

if (! -e $cdparanoia_path)
{
   print "\nWARNING: can't find cdparanoia at $cdparanoia_path!\n";
}


$user_input = "y";
while ( ( $user_input ne "n" ) && ( $user_input ne "N" ) ) {
   disc_cycle();
   print "\n";
   print "Try another disc? ([y]/n) ";
   $user_input = <STDIN>;
   chomp ($user_input);
}
print "Thanks for trying this software.\n";
exit;

my $disc_cycle;
sub disc_cycle {
  my $user_input;

  print "\n";
  print "---Insert CD into drive and press a key to begin---\n";
  print "\n";
  $user_input = <STDIN>;  # FIXME: find cleaner way to get a key
  $user_input = 2;
  print "getting CD info...\n";
  if (get_disc_info()) {
    ask_to_add();
  }
}

my $get_disc_info;
sub get_disc_info {
   my $ret = 0;
   my %config;
   my $cdh;

   $cd{artist} = undef;
   $cd{title} = undef;
   $cd{cat} = "unknown";
   $cd{id} = 0;
   $cd{tno} = 0;
   $cd{year} = "";
   @{$cd{track}} = ();

   # Try to find CD in $HOME/.cddb
   if ( -d "$cddb_dir" ) {
      print "Using data found in $cddb_dir\n";
      $cdh = read_local_cddb();
   }

   if (! $cdh)
   {
      $config{input} = 1;
      $config{CD_DEVICE} = $cddev;
      $config{CDDB_MODE} = "http";
      $config{CDDB_HOST} = "ca.freedb.org";
      $config{CDDB_PORT} = 8880;
      $cdh = get_cddb(\%config);
   }

   if ($cdh && $cdh->{title}) {
      %cd = %{$cdh};
      $ret = 1;
   } else {
      my ($id2, $tot, $toc);
      my $diskid=get_discids($cddev);
      $id2=$diskid->[0];
      $tot=$diskid->[1];
      $toc=$diskid->[2];
      my $id = sprintf("%08x", $id2); 

      print "no cddb entry found for $id\n";
      $ret = 0;
   }

   return $ret;

}

my $ask_to_add;
sub ask_to_add {
   my $user_input = "z";

   while (lc($user_input) ne "y") {
      print_report(\%cd);
      print "ok to rip? ([y]/n/e) ";

      $user_input = <STDIN>;
      chomp($user_input);
      if (lc($user_input) eq 'n') {
         warn "Aborting per user request...\n";
         return;
      } elsif (lc($user_input) eq 'e') {
         edit_cd_info(\%cd);
      } else {
         $user_input = "y";
         rip_tag(\%cd);
      }
   }
}

my $edit_cd_info;
sub edit_cd_info {
   my $cd = shift;
   my %backup_cd;
   my @backup_tracks;
   my $user_input = "z";

   %backup_cd = %{$cd};
   @backup_tracks = @{$cd->{track}};
   while ((lc($user_input) ne "s") && (lc($user_input) ne "x")) {
      print "\n[c] Category: $cd->{cat}\n";
      print "[d] DiscID  : $cd->{id}\n";
      print "[a] Artist  : $cd->{artist}\n";
      print "[t] Title   : $cd->{title}\n";
      print "[y] Year    : $cd->{year}\n";
      print "\n";

      my $num = 0;
      foreach my $track (@{$cd->{track}}) {
         $num++;
         print "[$num] $track\n";
      }
      print "\n[s] save\n";
      print "[x] abort and exit\n";
      print "choice? ([s]/c/d/a/t/y/#/x) ";

      $user_input = <STDIN>;
      chomp($user_input);
      if (lc($user_input) eq "c") {
         print "Category: ";
         $cd->{cat} = <STDIN>;
         chomp($cd->{cat});
      } elsif (lc($user_input) eq "d") {
         print "DiscID: ";
         $cd->{id} = <STDIN>;
         chomp($cd->{id});
      } elsif (lc($user_input) eq "a") {
         print "Artist: ";
         $cd->{artist} = <STDIN>;
         chomp($cd->{artist});
      } elsif (lc($user_input) eq "t") {
         print "Title: ";
         $cd->{title} = <STDIN>;
         chomp($cd->{title});
      } elsif (lc($user_input) eq "y") {
         print "Year: ";
         $cd->{year} = <STDIN>;
         chomp($cd->{year});
      } elsif (lc($user_input) eq "") {
         $user_input = "s";
      } elsif (lc($user_input) eq "x") {
         %{$cd} = %backup_cd;
         $cd->{track} = \@backup_tracks;
      } elsif (($user_input =~ m/^\d+$/) && ($user_input <= $cd->{tno})) {
         print "$user_input: ";
         ${$cd->{track}}[$user_input-1] = <STDIN>;
         chomp(${$cd->{track}}[$user_input-1]);
      }
   }
}

my $read_local_cddb;
sub read_local_cddb {
   my $cd;

   my ($id2, $tot, $toc);
   my $diskid=get_discids($cddev);
   $id2=$diskid->[0];
   $tot=$diskid->[1];
   $toc=$diskid->[2];
   my $id = sprintf("%08x", $id2); 
   $cd->{id} = $id;

   $cd->{artist} = undef;
   $cd->{title} = undef;
   $cd->{cat} = "unknown";
   $cd->{tno} = 0;
   $cd->{year} = "";
   @{$cd->{track}} = ();

   if (open (DATA, "$cddb_dir/$cd->{id}")) {

      while (<DATA>) {
         if ( m,^DTITLE=(.*) / (.*)$, ) {
            $cd->{artist} = $1;
            $cd->{title} = $2;
         }

         if ( m/^DGENRE=(.*)$/ or m/^210 (.*) $cd->{id}/ ) {
            $cd->{cat} = $1;
         }

         if ( m/^DYEAR=([0-9]*)$/ ) {
            $cd->{year} = $1;
         }

         if ( m/^TTITLE[0-9]*=(.*)$/ ) {
            ${$cd->{track}}[$cd->{tno}] = $1;
            $cd->{tno}++;
         }
      }
      close (DATA);

   } else {
      warn "Can't open $cddb_dir/$cd->{id}\n";
      $cd = undef;
   }

   return $cd;
}

my $print_report;
sub print_report {
   my $cd = shift;

   print "\nCategory: $cd->{cat}\n";
   print "DiscID  : $cd->{id}\n";
   print "Artist  : $cd->{artist}\n";
   print "Title   : $cd->{title}\n";
   print "Year    : $cd->{year}\n";
   print "Tracks  : $cd->{tno}\n";
   print "\n";

   my $num = 0;
   foreach my $track (@{$cd->{track}}) {
      $num++;
      print "$num. $track\n";
   }
   print "\n";

   $num = 0;
   foreach my $track (@{$cd->{track}}) {
      $num++;
      if ($num < 10) {
         $num2 = "0$num";
      } else {
         $num2 = $num;
      }

      $fname = fixname("$cd->{artist}-$cd->{title}-$num2-$track.mp3");

      print "$num. $track\n";
      print $fname . "\n";
   }
   print "\n";

}

my $rip_tag;
sub rip_tag {
   my $cd = shift;

   $cmd1 = $cdparanoia_path . " -d $cddev -v -B 1-";
   system($cmd1);

   $cmd2 = $id3ren_path . " -quiet -tag -tagonly";
#   $cmd2 .= qq( -artist=") . escape_quotes($cd->{artist}) .
#            qq(" -album=") . escape_quotes($cd->{title}) . qq(");
   $cmd2 .= qq( -artist=) . (shell_quote $cd->{artist}) .
            qq( -album=) . (shell_quote $cd->{title});
   if ($cd->{year} eq "") {
      $cmd2 .= qq( -noyear);
   } else {
#      $cmd2 .= qq( -year=") . escape_quotes($cd->{year}) . qq(");
      $cmd2 .= qq( -year=) . (shell_quote $cd->{year});
   }
   $cmd2 .= qq( -nogenre -comment="ripped by grub");
   $num = 0;
   foreach $track (@{$cd->{track}}) {
      $num++;
      if ($num < 10) {
         $num2 = "0$num";
      } else {
         $num2 = $num;
      }

      $cmd3 = $cmd2;
      if ($track eq "") {
         $cmd3 .= qq( -track="$num" -song="");
      } else {
#         $cmd3 .= qq( -track="$num" -song="$track");
         $cmd3 .= qq( -track="$num" -song=) . (shell_quote $track);
      }

      $fname = fixname(qq($cd->{artist}-$cd->{title}-$num2-$track.mp3));

      $cmd3 .= " $fname";

      # encode mp3
      $cmd4 = $lame_path . qq( -h -b 320 track$num2.cdda.wav '$fname');
      system($cmd4);

      # tag new mp3, delete .wav
      system($cmd3);
      system("rm -f track$num2.cdda.wav");
   }
   system("rm -f *.wav");

   $arname = fixname($cd->{artist});

   $alname = fixname($cd->{title});

   system("mkdir $arname");
   system("mkdir $arname/$alname");
   system("mv *.mp3 $arname/$alname");

   print "\n";
}

my $escape_quotes;
sub escape_quotes {

   my $in = shift;
   my $out = "";

   if ($in && ($in ne "")) {
      $out = $in;
      $out =~ s/"/\\"/g;
   }

   return $out;
}
