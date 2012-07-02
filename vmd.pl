#!/usr/bin/perl
 
# vmd.pl - download tracks from vk.com
# (c) Genaev Misha 2012 | http://genaev.com/pages/vdm

use strict;
use warnings;
use VK::App 0.06;
use File::HomeDir;
use Getopt::Long;
use Encode;

my $version   = '0.01';
my $app_name  = 'vmd-'.$version;
my $home_page = 'http://genaev.com/pages/vdm';

my $msg_session_gen = "Используйте следующею команду для его генерации:\n".
  "$0 --login <ваш email или номер телефона> --password <ваш пароль> --api_id <ID приложения>\n".
  "Заметьте, $app_name не хранит ваш пароль на жестком диске, используя файл с сессией для авторизации.\n".
  "Эту команду надо выполнить всего один раз!\n";

my $msg_help = "Программа $app_name для скачивания музыки из vk.com\n".
  "Для использования программы надо получить api_id, перейдя по ссылке:\n ".
  "http://vk.com/apps.php?act=add\n".
  "После этого надо создать файл с сессией.\n".
  "$msg_session_gen".
  "\nТеперь можно скачивать музыку\n".
  "  Скачивание музыки у пользователей:\n".
  "  Если страница пользователя http://vk.com/genaev или http://vk.com/id2302071\n".
  "  то для того что бы скачать его музыку надо запустить:\n".
  "  $0 --uid genaev\n".
  "  $0 --uid 2302071\n".
  "  Скачивание музыки из групп:\n".
  "  Если страница группы http://vk.com/teamfly то надо запустить\n".
  "  $0 --gid teamfly\n".
  "Загрузка музыки происходит в текущею директорию.\n".
  "Синхронизация происходит автоматически, если трек уже скачан, второй раз он скачиваться не будет.\n".
  "\nПосетите домашнею страницу проекта для получения новых версий и дополнительной информации:\n".
  "$home_page\n";

my $msg_authorize_ok = "Авторизация прошла успешно!\n".
  "Выполните '$0 --help' что бы узнать как скачивать музыку.\n";
  
my $msg_authorize_fail = "Упс! Что-то пошло не так и авторизация не удалась.\n".
  "Проверьте правильность введенного логина, пароля и api_id.\n".
  "Заметьте, что логин и пароль нужно писать в кавычках, например:\n".
  "--login 'my\@email.ru' --password 'my_long_password'\n";

my ($help_flag,$version_flag,
    $login,$password,$api_id,
    $uid,$gid,
    );

GetOptions("help"       => \$help_flag,
           "version"    => \$version_flag,
           "login=s"    => \$login,
           "password=s" => \$password,
           "api_id=i"   => \$api_id,
           "uid=s"      => \$uid,
           "gid=s"      => \$gid,
#           "pid=s"      => \$pid,
          );

if ($help_flag) {
  print $msg_help;
  exit 0;
}
elsif ($version_flag) {
  print "$app_name\n";
  exit 0;
}
elsif ($login && $password && $api_id) {
  my ($cookie_file,$api_id_file) = &cookie_and_api_id_files;
  my $vk;  
  eval {
    $vk = VK::App->new(
       login       => $login,
       password    => $password,
       api_id      => $api_id,
       cookie_file => $cookie_file, # Name of the file to restore cookies from and save cookies to
    );
  };
  if ($@ || !$vk || !$vk->uid) {
    print $msg_authorize_fail;
    exit 1;
  }
  else {
    &api_id_to_file($api_id_file,$api_id);
    print $msg_authorize_ok;
    exit 0;
  }
}
elsif ($uid) {
  my $vk = &app;
  my $user = $vk->request('getProfiles',{uid=>$uid,fields=>'uid'}); # Get user id by name
  if (exists $user->{response}->[0]->{uid}) {
    my $tracks = $vk->request('audio.get',{uid=>$user->{response}->[0]->{uid}}); # Get a list of tracks by uid
    &download($vk,$tracks);
  }
  else {
    print "Не могу найти пользователя с uid '$uid'\n";
    exit 1;
  }
}
elsif ($gid) {
  my $vk = &app;
  my $tracks = $vk->request('audio.get',{gid=>$gid}); # Get a list of tracks by gid
  &download($vk,$tracks);  
}
else {
  print $msg_help;
  exit 0;
}

sub check_file_exists {
  my $id = shift;
  return 1 if (-e $id);
  return 0;
}

sub download {
  my $vk     = shift;
  my $tracks = shift;
  
  &check_tracks($tracks);
  
  my $ua = $vk->ua; # Get LWP::UserAgent object
  $|=1;
  my $i = 0;
  my $n = scalar @{$tracks->{response}}; # number of tracks
  foreach my $track (@{$tracks->{response}}) {
    $i++;
    my $aid    = $track->{aid};
    my $url    = $track->{url};
    my $artist = $track->{artist};
    my $title  = $track->{title};
    $artist = &clean_name($artist, without_punctuation => 1);
    $title  = &clean_name($title, without_punctuation => 1);
    
    my $mp3_name = $artist.'-'.$title.'-'.$aid.'.mp3';
    my $mp3_filename = $aid.'.mp3';
    if (&check_file_exists($mp3_filename) == 1) {
      print "$i/$n Уже скачан $mp3_name - ОК\n";
      next;
    }
	else{
    print "$i/$n Скачиваю $mp3_name";
    my $req = HTTP::Request->new(GET => $url);
    my $res = $ua->request($req, $mp3_filename);
    if ($res->is_success) {
      print " - ОК\n";
    }
    else {
      print " - ", $res->status_line, "\n";
    }
  }
  }
}

sub clean_name {
 # Get string (part of the filename) and (optionally) parameters hash.
 # Return string which is safe for filename in windows.
  my $name = shift;
  my %par = ( name_length         => 256,
              without_punctuation => 0,
              @_);
              
  # Spaces
  chomp $name;
  $name =~ s/^\s+//;
  $name =~ s/\s+$//;
  $name =~ s/\s+/ /g;

  # Remove ascii 0..31 and <>:"/\|?* which are illegal for windows
  # http://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx
  $name =~ s/[\0-\37<>:"\/\\|?*]+//g;

  if ($par{without_punctuation}) {
  # Clean from spaces and punctuation
  # Punctuation: !"#$%&'()*+,-./:;<=>?@[\]^_`{|}~
    $name =~ s/[\s[:punct:]]+$//;
    $name =~ s/^[\s[:punct:]]+//;
    $name =~ s/[\s[:punct:]]+/_/g;
  }

  # Truncate name
  if ($par{name_length} < length($name)) {
    $name = substr $name, 0, $par{name_length};
  }

  # Undesired characters in the begin and in the end
  $name =~ s/^[-_;\]}).,\s]+//;
  $name =~ s/[-_;[{(.,\s]+$//;
  
  decode_utf8($name) ;
  return $name;
}

sub check_tracks {
  my $tracks = shift;
  return 1
  if ($tracks && exists $tracks->{response} && scalar @{$tracks->{response}} > 0 && exists $tracks->{response}->[0]);
  print "Упс! Треков которые вы хотите скачать уже нет или у вас нет прав доступа для их прослушивания.\n";
  exit 1;
}

sub app {
  my ($cookie_file,$api_id_file) = &cookie_and_api_id_files;
  unless (-f "$cookie_file" && -f "$api_id_file") {
    print "Файл с сессией для авторизации или api_id приложения не найден.\n",
    $msg_session_gen;
    exit 1;
  }
  my $vk;  
  eval {
    $vk = VK::App->new(
       api_id      => &api_id_from_file($api_id_file),
       cookie_file => $cookie_file, # Name of the file to restore cookies from and save cookies to
    );
  };
  if ($@ || !$vk || !$vk->uid) {
    print $msg_authorize_fail;
    exit 1;
  }
  return $vk;
}

sub cookie_and_api_id_files {
  my $data_dir =  File::HomeDir->my_data;
  die "Can't get user's data directory" unless $data_dir;
  $data_dir .= '/'.$app_name;
  mkdir $data_dir,0700 or die "Can't create app config directory" unless(-d $data_dir);

  my $cookie_file = $data_dir.'/.cookie';
  my $api_id_file = $data_dir.'/.api_id';
  
  return ($cookie_file,$api_id_file);
}

sub api_id_from_file {
  my $file = shift;
  open F, "$file" or die $!;
  my $id = <F>;
  close F;
  chomp($id);
  die "Bad api_id" if (!$id || $id !~ /^\d+$/);
  return $id;
}

sub api_id_to_file {
  my $file = shift;
  my $id = shift;
  open F, ">$file" or die $!;
  print F "$id\n";
  close F;
}

__END__

