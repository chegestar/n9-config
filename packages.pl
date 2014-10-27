#!/usr/bin/perl
use strict;
use warnings;

my $pkgConfig = '/etc/package-manager/config';
my $ipmagicCmd = "n9";

my @jobs = qw(
  xsession/applauncherd
  xsession/applifed
  xsession/conndlgs
  xsession/sysuid
);

my @packagesToRemove = qw(
  wxapp apnews realgolf2011 gof2 nfsshift
  angrybirdsfreemagic
  ovi-music-store morpheus morpheus-guard

  mp-harmattan-001-pr
  facebook facebookqml libqt-facebook facebook-meego
  twitter twitter-qml libmeegotwitter1 twitter-meego
);

my $normalPackages = {
  '1' => [qw(
    bash vim rsync wget git sudo
  )],
  '2' => [qw(
    perl bash-completion python
    htop lftp
    x11-utils xresponse
    meecast
    aptitude
    xmimd
    imagemagick
    python-pyside.qtgui python-qmsystem python-pyside.qtdeclarative
    python-qtmobility.multimediakit
  )],
  '3' => [qw(
    meefox
    screen
    cameraplus
    qtbigtext
    n9-button-monitor
    modrana
  )],
  '4' => [qw(
    ad-hac
    wireless-tools
    qtodo brujula dropcache-mdn
    qml2048
  )],
  '5harmattan-dev' => [qw(
    linux-kernel-headers
    gcc make
    nmap curl openvpn
    libterm-readkey-perl
    python-apt
    mcetools bzip2 sqlite3
  )],
};
my $extraPackages = {
  '6inceptedrepo' => [qw(
    busybox-power-noaegis
    system-ui-brightness-control
    led-event-notifier
    mt-toggles bluetooth-toggle flashlight-toggle n9bm-toggle
  )],
};

my $repoDir = 'repos';
my $debDir = 'debs-custom';
my $debDestPrefix = '/opt';
my $env = 'AEGIS_FIXED_ORIGIN=com.nokia.maemo';

sub runRemote(@){
  system $ipmagicCmd, "-s", @_;
  die "error running '$ipmagicCmd -s @_'\n" if $? != 0;
}
sub readProcRemote(@){
  return `$ipmagicCmd -s @_`;
  die "error running '$ipmagicCmd -s @_'\n" if $? != 0;
}
sub host(){
  my $host = `$ipmagicCmd`;
  chomp $host;
  return $host;
}

sub installPackages($$);
sub removePackages();
sub setupRepos();
sub installDebs();

sub main(@){
  my $reinstall = shift if @_ > 0 and $_[0] =~ /--reinstall/g;

  my $arg = shift;
  $arg = 'all' if not defined $arg;
  my $valid = join '|', qw(all repos packages extra remove debs);
  if(@_ > 0 or $arg !~ /^($valid)/){
    die "Usage: $0 [--reinstall] TYPE {type must start with one of: $valid}\n";
  }
  if($arg =~ /^(all|repos)/){
    if(setupRepos()){
      runRemote "$env apt-get update";
    }
  }
  installPackages($normalPackages, $reinstall) if $arg =~ /^(all|packages)/;
  removePackages() if $arg =~ /^(all|remove)/;
  installDebs() if $arg =~ /^(all|debs|debs-custom)/;
  installPackages($extraPackages, $reinstall) if $arg =~ /^(all|extra)/;
}


sub getRepos(){
  #important to sort the files and not the lines
  my $cmd = "'ls /etc/apt/sources.list.d/*.list | sort | xargs cat'";
  return readProcRemote $cmd;
}

sub setupRepos(){
  if(not -d $repoDir){
    print "skipping repo setup; \"$repoDir\" doesnt exist\n";
    return 0;
  }
  my $before = getRepos();
  my $host = host();

  print "Copying $repoDir => remote\n";
  system "scp $repoDir/* root\@$host:/etc/apt/sources.list.d/";
  print "\n\n";

  print "Content of the copied lists:\n";
  system "cat $repoDir/*.list";
  print "\n\n";

  runRemote '
    echo INSTALLING KEYS:
    for x in /etc/apt/sources.list.d/*.key; do
      echo $x
      apt-key add "$x"
    done
  ';
  
  my $after = getRepos();
  return $before ne $after;
}

sub installPackages($$){
  my $pkgGroups = shift;
  my $reinstall = shift;
  my @opts;
  push @opts, "--reinstall" if defined $reinstall;
  print "\n\n";
  for my $pkgGroup(sort keys %$pkgGroups){
    my @packages = @{$$pkgGroups{$pkgGroup}};
    print "Installing group[$pkgGroup]:\n----\n@packages\n----\n";
    runRemote ''
      . "yes |"
      . " $env apt-get install"
      . " -y --allow-unauthenticated"
      . " @opts"
      . " @packages";
  }
}

sub getInstalledVersion($){
  my $name = shift;
  our %packages;
  if(keys %packages == 0){
    my $dpkgStatus = readProcRemote "cat /var/lib/dpkg/status";
    for my $pkg(split "\n\n", $dpkgStatus){
      my $name = ($pkg =~ /Package: (.*)\n/) ? $1 : '';
      my $status = ($pkg =~ /Status: (.*)\n/) ? $1 : '';
      my $version = ($pkg =~ /Version: (.*)\n/) ? $1 : '';

      $packages{$name} = $version if $status eq "install ok installed";
    }
  }
  return $packages{$name};
}

sub getArchiveVersion($){
  my $debArchive = shift;
  my $status = `dpkg --info $debArchive`;
  if($status =~ /^ Version: (.*)/m){
    return $1;
  }else{
    return undef;
  }
}

sub getArchivePackageName($){
  my $debArchive = shift;
  my $status = `dpkg --info $debArchive`;
  if($status =~ /^ Package: (.*)/m){
    return $1;
  }else{
    return undef;
  }
}

sub removePackages(){
  if(@packagesToRemove == 0){
    print "skipping removal, no packages to remove\n";
    return;
  }
  print "\n\nInstalling the deps for removed packages to unmarkauto\n";
  my %deps;
  for my $line(readProcRemote "apt-cache depends @packagesToRemove"){
    if($line =~ /  Depends: ([^<>]*)/){
      my $pkg = $1;
      chomp $pkg;
      $deps{$pkg} = 1;
    }
  }
  for my $pkg(@packagesToRemove){
    delete $deps{$pkg};
  }
  my $depInstallCmd = "$env apt-get install --force-yes -y \\\n";
  for my $dep(keys %deps){
    $depInstallCmd .= "  $dep \\\n";
  }
  print $depInstallCmd;
  runRemote $depInstallCmd;

  print "\n\nChecking uninstalled packages\n";
  my $removeCmd = "$env dpkg --purge --force-all";
  for my $pkg(@packagesToRemove){
    $removeCmd .= " $pkg";
  }
  if(@packagesToRemove > 0){
    runRemote $removeCmd;
  }
}

sub isVirtualProvided($$){
  my $pkg = shift;
  my $virtualPkg = shift;
  my @provides = readProcRemote "apt-cache show $pkg | grep ^Provides";
  for my $line(@provides){
    if($line =~ / $virtualPkg(,|$)/){
      return 1;
    }
  }
  return 0;
}

sub isAlreadyInstalled($$$){
  my $debFile = shift;
  my %virtualPackages = %{shift()};
  my %triggers = %{shift()};

  my $packageName = getArchivePackageName $debFile;
  if(defined $triggers{$packageName}){
    $debFile = $triggers{$packageName};
    $packageName = getArchivePackageName $debFile;
  }
  if(defined $virtualPackages{$packageName}){
    my $virt = $virtualPackages{$packageName};
    if(not isVirtualProvided($packageName, $virt)){
      print "  {virtual package $virt not provided by $packageName}\n";
      return 0;
    }
  }
  my $archiveVersion = getArchiveVersion $debFile;
  my $installedVersion = getInstalledVersion $packageName;
  if(not defined $archiveVersion or not defined $installedVersion){
    return 0;
  }else{
    return $archiveVersion eq $installedVersion;
  }
}

sub installDebs(){
  my @debs = `cd $debDir; ls */*.deb`;
  chomp foreach @debs;
  
  print "\n\nSyncing $debDestPrefix/$debDir to $debDestPrefix on dest:\n";
  my $host = host();
  system "rsync $debDir root\@$host:$debDestPrefix -av --progress --delete";

  my %virtualPackages = (
    'system-ui' => 'unrestricted-system-ui'
  );

  my $powerpackTriggerDeb =
    `ls $debDir/7powerpack/meegotouchtheme-ppack-fixes*.deb`;
  chomp $powerpackTriggerDeb;

  my @powerpackDebs =
    map {chomp; getArchivePackageName $_} `ls $debDir/7powerpack/*.deb`;

  my %triggers;
  $triggers{$_} = $powerpackTriggerDeb foreach @powerpackDebs;

  my $count = 0;
  print "\n\nChecking installed versions\n";
  my $cmd = '';
  for my $job(@jobs){
    $cmd .= "stop $job\n";
  }
  for my $deb(@debs){
    my $localDebFile = "$debDir/$deb";
    my $remoteDebFile = "$debDestPrefix/$debDir/$deb\n";
    if(not isAlreadyInstalled($localDebFile, \%virtualPackages, \%triggers)){
      $count++;
      print "...adding $localDebFile\n";
      $cmd .= "$env dpkg -i $remoteDebFile\n";
      $cmd .= "if [ \$? != 0 ]; then "
              . "$env apt-get -f install -y --allow-unauthenticated; "
              . "fi\n";
    }else{
      print "Skipping already installed $deb\n";
    }
  }
  for my $job(@jobs){
    $cmd .= "start $job\n";
  }
  $cmd = "
    set -x;
    DR=`cat $pkgConfig | grep disableReboot | sed s/disableReboot=//`
    sed -i s/disableReboot=.*/disableReboot=1/ $pkgConfig
    $cmd
    sed -i s/disableReboot=.*/disableReboot=\$DR/ $pkgConfig
  ";

  print "\n\nInstalling debs\n";
  if($count > 0){
    runRemote $cmd;
  }
}

&main(@ARGV);
