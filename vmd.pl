#!/usr/bin/perl
 
# vmd.pl - download tracks from vk.com
# (c) Genaev Misha 2012 | http://genaev.com/pages/vdm

use strict;
use warnings;
use VK::App 0.10;
use File::HomeDir;
use Getopt::Long;
use Encode;
use File::Copy;
use Thread::Pool::Simple;
use LWP::UserAgent;
use IO::File;

my $version   = '0.05';
my $app_name  = 'vmd-'.$version;
my $home_page = 'http://genaev.com/vmd';

my $windows = 0;
$windows = 1 if ($^O =~ /win/i && $^O !~ /darwin/i);

my $msg_session_gen = "Используйте следующую команду для его генерации:\n".
  "$0 --login <ваш email или номер телефона> --password <ваш пароль> --api_id <ID приложения>\n".
  "Заметьте, $app_name не хранит ваш пароль на жестком диске, используя файл с сессией для авторизации.\n".
  "Эту команду надо выполнить всего один раз!\n";

my $msg_help = 
  "$app_name Copyright (C) 2012 Миша Генаев\n".
  "web site: http://genaev.com/pages/vdm\n\n".
  "Программа $app_name для скачивания музыки из vk.com\n".
  "Для использования программы надо получить api_id, перейдя по ссылке:\n ".
  "http://vk.com/apps.php?act=add\n".
  "После этого надо создать файл с сессией.\n".
  "$msg_session_gen".
  "\nТеперь можно скачивать музыку\n".
  "  Скачивание музыки у пользователей:\n".
  "  Если страница пользователя http://vk.com/genaev или http://vk.com/id2302071\n".
  "  то для того, чтобы скачать его музыку, надо запустить:\n".
  "  $0 --uid genaev\n".
  "  $0 --uid 2302071\n".
  "  Скачивание музыки из групп:\n".
  "  Если страница группы http://vk.com/teamfly, то надо запустить\n".
  "  $0 --gid teamfly\n".
  "  Скачивание музыки из плей листов и отдельных страниц страниц:\n".
  "  $0 --page 'http://vk.com/audio?album_id=27680175&id=23962687'\n".
  "  Получение ссылок на mp3 файлы и создание плей листов:\n".
  "  $0 --gid 'dubstep light' --m3u play_list.m3u\n".
  "\nВажно!\n".
  "Под Windows параметры командной строки надо вводить в двойных кавычках!\n".
  "Загрузка музыки происходит в текущую директорию.\n".
  "Синхронизация происходит автоматически, если трек уже скачан, второй раз он скачиваться не будет.\n".
  "Доступны и другие режимы скачивания музыки!\n".
  "\nПосетите домашнюю страницу проекта для получения новых версий и дополнительной информации:\n".
  "$home_page\n";

my $msg_authorize_ok = "Авторизация прошла успешно!\n".
  "Выполните '$0 --help', чтобы узнать, как скачивать музыку.\n";
  
my $msg_authorize_fail = "Упс! Что-то пошло не так и авторизация не удалась.\n".
  "Проверьте правильность введенного логина, пароля и api_id.\n".
  "Заметьте, что логин и пароль нужно писать в кавычках, например:\n".
  "--login 'my\@email.ru' --password 'my_long_password'\n";

my ($help_flag,$version_flag,
    $login,$password,$api_id,
    $uid,$gid,$aid,$rec,$page,$m3u,
    );

my $trh = 2; # кол-во потоков по умолчанию

GetOptions("help"       => \$help_flag,
           "version"    => \$version_flag,
           "login=s"    => \$login,
           "password=s" => \$password,
           "api_id=i"   => \$api_id,
           "uid=s"      => \$uid,
           "gid=s"      => \$gid,
           "aid=s"      => \$aid,
           "rec=i"      => \$rec,
           "trh=i"      => \$trh,
           "page=s"     => \$page,
           "m3u=s"     => \$m3u,
          );

$api_id = 2998239 unless $api_id;

my $m3u_fh = IO::File->new("> $m3u") if $m3u;
print $m3u_fh "#EXTM3U\n" if $m3u_fh;

# Инициализация пула воркеров
my $pool = Thread::Pool::Simple->new(
  min => $trh, max => $trh+2, load => $trh, # минимум 2 воркеров, если очередь больше 2 - 4
  do => [\&download_track],                 # функция для воркера
);

our $vk; # VK::App object

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
elsif ($rec) {
  $vk = &app;
  my $music;
  my $for_download;
  if ($uid) {
    my $user = $vk->request('getProfiles',{uid=>$uid,fields=>'uid'}); # Get user id by name
    if (exists $user->{response}->[0]->{uid}) {
      $uid = $user->{response}->[0]->{uid};
    }
    else {
      $uid = $vk->uid;
    }
  }
  else {
    $uid = $vk->uid;
  }
  my $friends = $vk->request('friends.get',{uid=>$uid});
  push @{$friends->{response}}, $vk->uid; # and I too
  my $total_f = scalar(@{$friends->{response}});
  $|=1;
  print "У меня $total_f друга\n";
  print "Получение музыки друзей...\n";
  my $i = 0;
  my $j = 0;
  foreach my $fid (@{$friends->{response}}) {
    $i++;
    print "$i/$total_f";
    my $tracks = $vk->request('audio.get',{uid=>$fid});
    foreach my $track (@{$tracks->{response}}) {
      $j++;
      my $aid = $track->{artist}.'-'.$track->{title};
      $music->{$aid}->{count} = 0 unless exists $music->{$aid}->{count}; 
      $music->{$aid}->{count}++;
      $music->{$aid}->{track} = $track;
    }
    print " - OK\n";
  }
  print "Всего получено $j треков\n";
  foreach my $aid (keys %{$music}) {
    push @{$for_download}, $music->{$aid}->{track} if $music->{$aid}->{count} >= $rec;
  }
  my $cross_count = 0;
  $cross_count = scalar @{$for_download} if $for_download;
  print "И найдено $cross_count пересечений\n";
  if ($cross_count) {
    foreach my $track (@{$for_download}) {
      my $aid = $track->{artist}.'-'.$track->{title};
      my $res->{response} = [$track];
      &download($res,'0'.$music->{$aid}->{count}."-");
    }
  }
}
elsif ($uid) {
  $vk = &app;
  my $user = $vk->request('users.get',{uids=>$uid,fields=>'uid'}); # Get user id by name
  if (exists $user->{response}->[0]->{uid}) {
    my $tracks = $vk->request('audio.get',{uid=>$user->{response}->[0]->{uid}}); # Get a list of tracks by uid
    &download($tracks);
  }
  else {
    print "Не могу найти пользователя с uid '$uid'\n";
    exit 1;
  }
}
elsif ($gid) {
  $vk = &app;
  unless ($gid =~ /\d+/) {
    my $group = $vk->request('groups.search',{q=>$gid,count => 1});
    $gid = $group->{response}->[1]->{gid} if ($group->{response}->[0]);
  }
  my $tracks = $vk->request('audio.get',{gid=>$gid}); # Get a list of tracks by gid
  &download($tracks);  
}
elsif ($aid) {
  $vk = &app;
  my $tracks = $vk->request('audio.getById',{audios=>$aid}); # Get a list of tracks by aid
  &download($tracks);
}
elsif ($page) {
  $vk = &app;
  my $ua = $vk->ua;
  $ua->agent("Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.0)");
  my $res = $ua->get($page);
  return 0 unless $res->is_success;
  my $content = $res->decoded_content;
  my $audios;
  push @{$audios}, $+ while ($content =~ /id=\"audio([\d_-]+)\"/g);
  return 0 unless @{$audios};
  my $tracks = $vk->request('audio.getById',{audios=>join(',',@{$audios})});
  &download($tracks);
}
else {
  print $msg_help;
  exit 0;
}

$pool->join();

sub check_file_exists {
  my $file_name = shift;
  my $id = $1 if $file_name =~ /-(\d+)\.mp3$/;
  foreach (<*$id.mp3>) {
    move($_,$file_name) if ($file_name ne $_);
    return 1;
  }
  return 0;
}

sub download {
  my $tracks = shift;
  my $prefix = shift; $prefix = "" unless $prefix;

  &check_tracks($tracks);
  
  $|=1;
  my $i = 0;
  my $n = scalar @{$tracks->{response}}; # number of tracks

  foreach my $track (@{$tracks->{response}}) {
    $i++;
    my $aid      = $track->{aid};
    my $url      = $track->{url};
    my $artist   = $track->{artist};
    my $title    = $track->{title};
    my $duration = $track->{duration};
    $artist = &clean_name($artist, without_punctuation => 1);
    $title  = &clean_name($title, without_punctuation => 1);
    $artist = encode_utf8($artist);
    $title  = encode_utf8($title);
    
    unless ($m3u_fh) {
      my $mp3_filename = $prefix.$artist.'-'.$title.'-'.$track->{aid}.'.mp3';
      if ($windows) {
        Encode::from_to($mp3_filename, 'utf-8', 'windows-1251');
      }
      if (&check_file_exists($mp3_filename) == 1) {
        print "$i/$n Уже скачан $mp3_filename - ОК\n";
        next;
      }
      $pool->add($url,$mp3_filename,$i,$n);
    }
    else {
      print $m3u_fh "#EXTINF:$duration,$artist - $title\n";
      print $m3u_fh "$url\n";
    }
   
  }
}

sub download_track {
  my $url      = shift;
  my $filename = shift;
  my $i        = shift;
  my $n        = shift;
  my $ua = LWP::UserAgent->new; # Get LWP::UserAgent object
  print "$i/$n Скачиваю $filename ...\n";
  my $req = HTTP::Request->new(GET => $url);  
  my $res = $ua->request($req, $filename.'.tmp');
  move($filename.'.tmp',$filename);
  print "$i/$n $filename";
  if ($res->is_success) {
    print " - ОК\n";
  }
  else {
    print " - ", $res->status_line, "\n";
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
    $name =~ s/[\s[:punct:]\p{P}\p{Z}\p{M}\p{S}\p{C}]+$//;
    $name =~ s/^[\s[:punct:]\p{P}\p{Z}\p{M}\p{S}\p{C}]+//;
    $name =~ s/[\s[:punct:]\p{P}\p{Z}\p{M}\p{S}\p{C}]+/_/g;
  }
  
  # Truncate name
  if ($par{name_length} < length($name)) {
    $name = substr $name, 0, $par{name_length};
  }

  # Undesired characters in the begin and in the end
  $name =~ s/^[-_;\]}).,\s]+//;
  $name =~ s/[-_;[{(.,\s]+$//;

  return $name;
}

sub check_tracks {
  my $tracks = shift;
  return 1
  if ($tracks && exists $tracks->{response} && scalar @{$tracks->{response}} > 0 && exists $tracks->{response}->[0]);
  print "Упс! Треков, которые вы хотите скачать, уже нет, или у вас нет прав доступа для их прослушивания.\n";
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
