#!/bin/bash
#
# ***** BEGIN LICENSE BLOCK *****
# Zimbra Collaboration Suite Server
# Copyright (C) 2009, 2010, 2011, 2013, 2014, 2015, 2016 Synacor, Inc.
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software Foundation,
# version 2 of the License.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with this program.
# If not, see <https://www.gnu.org/licenses/>.
# ***** END LICENSE BLOCK *****


#-------------------- Configuration ---------------------------

	currentScript=`basename $0 | cut -d "." -f 1`
	currentPackage=`echo ${currentScript}build | cut -d "-" -f 2`


#-------------------- Package Script ---------------------------


	echo -e "\tCreate package directories" >> ${buildLogFile}
	mkdir -p ${repoDir}/zm-build/${currentPackage}/opt/zimbra/conf
	mkdir -p ${repoDir}/zm-build/${currentPackage}/DEBIAN

	echo -e "\tCopy package files" >> ${buildLogFile}
	cp ${repoDir}/zm-convertd-store/conf/httpd.conf ${repoDir}/zm-build/${currentPackage}/opt/zimbra/conf/httpd.conf
	cp ${repoDir}/zm-aspell/conf/php.ini ${repoDir}/zm-build/${currentPackage}/opt/zimbra/conf/php.ini
	(cd ${repoDir}/zm-build/${currentPackage}; find . -type f ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' -print0 | xargs -0 md5sum | sed -e 's| \./| |' >  ${repoDir}/zm-build/${currentPackage}/DEBIAN/md5sums)
	cat ${repoDir}/zm-build/rpmconf/Spec/zimbra-apache.deb | sed -e "s/@@VERSION@@/${release}.${buildNo}.${os/_/.}/" -e "s/@@branch@@/${buildTimeStamp}/" -e "s/@@ARCH@@/${arch}/" > ${repoDir}/zm-build/${currentPackage}/DEBIAN/control

	echo -e "\tCreate debian package" >> ${buildLogFile}
	(cd ${repoDir}/zm-build/${currentPackage}; dpkg -b ${repoDir}/zm-build/${currentPackage} ${repoDir}/zm-build/${arch} )

	if [ $? -ne 0 ]; then
		echo -e "\t### ${currentPackage} package building failed ###" >> ${buildLogFile}
	else
		echo -e "\t*** ${currentPackage} package successfully created ***" >> ${buildLogFile}
	fi