vdm - программа для скачивания музыки из vk.com
===================

## Использование
Для получения информации об использовании программы запустите её без параметров
или посетите домашнию страницу проекта.

## Установка
Для работы скрипта необходима установка некоторых библиотек и модулей для perl 

### Debian:
```
apt-get install libssl-dev
cpan install IO::Socket::SSL
cpan install File::HomeDir
cpan install VK::App
```
### Ubuntu
```
cpan install LWP
cpan install LWP::Protocol::https
cpan install JSON
cpan install IO::Socket::SSL
cpan install File::HomeDir
cpan install VK::App
```
В убунте не хочет собираться пакет VK::App - ругается на незакрытую скобку. 
Действительно, так и есть, лезем в папку /home/user/.cpan/build/VK-App-0.06-??????
открываем любимым редактором файл Makefile.PL и правим предпоследнюю строчку, добавляя в ее конец "}"
```
	homepage    => 'http://genaev.com/',
	license     => 'http://dev.perl.org/licenses/',
	},}
);
```

Copyright (C) 2012 Миша Генаев
email: misha.genaev@gmail.com
web site: http://genaev.com/pages/vdm

