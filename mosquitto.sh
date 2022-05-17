#!/bin/env bash

current=`pwd`

echo "current:$current"

Greet() {

str="ok Install immediately $yes"

echo $str
}
          echo "--->"
          echo "     You are going to install mosquitto-ha , right ?"
read yes

val=$(Greet)
          echo -e "---> $val"

SEARCH=$(find / -name ansible-2.9.13 |grep -w mqtt-tls)

search_pkg () {
    for start in $SEARCH;
           do cd $start;
           done
    rpm -ivh --replacefiles --replacepkgs --nodeps *.rpm
}
search_pkg

cd $current

echo `pwd`

chmod o-w .

exit 0
