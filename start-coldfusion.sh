#!/bin/bash

# METHODS

# CLI filename. Empty if not specified
filename=$2

# Start ColdFusion in the foreground
start()
{
	if [ -e /opt/startup/disableScripts ]; then
		
		echo "Skipping ColdFusion setup"
		startColdFusion 0
				
	else
	
		restartRequired=0

		updateWebroot
        
		updatePassword

		updateLanguage

		setupSerialNumber

		startColdFusion 0 

        	importCAR
		tmpRestartRequired=$?
		if [ $restartRequired != 1 ]; then
                        restartRequired=$tmpRestartRequired
                fi

		setupExternalAddons
		tmpRestartRequired=$?
                if [ $restartRequired != 1 ]; then
                        restartRequired=$tmpRestartRequired
                fi

		setupExternalSessions
		tmpRestartRequired=$?
                if [ $restartRequired != 1 ]; then
                        restartRequired=$tmpRestartRequired
                fi

        	invokeCustomCFM
		tmpRestartRequired=$?
                if [ $restartRequired != 1 ]; then
                        restartRequired=$tmpRestartRequired
                fi

		# Secure profile enablement goes last. This is to faciliate the scripts to execute SecureProfile disabled sections
		enableSecureProfile
		tmpRestartRequired=$?
                if [ $restartRequired != 1 ]; then
                        restartRequired=$tmpRestartRequired
                fi

		cleanupTestDirectories
		
		# Final action - Restart CF for changes to take effect		
        	if [ $restartRequired = 1 ]; then
                	startColdFusion 1
        	fi

		echo 'Do not delete. Avoids script execution on container start' >  /opt/startup/disableScripts        
	fi

	# Listen to start a daemon

	touch /opt/coldfusion/cfusion/logs/coldfusion-out.log
	tail -f /opt/coldfusion/cfusion/logs/coldfusion-out.log
}

startColdFusion(){

        # Stop ColdFusion if $1 = 1
        if [ $1 = 1 ]; then
		echo "Restarting ColdFusion"
                /opt/coldfusion/cfusion/bin/coldfusion stop
	else
		echo "Starting ColdFusion"
        fi

        # Start ColdFusion Service
        /opt/coldfusion/cfusion/bin/coldfusion start

        # Wait for ColdFusion startup before returning control
       	checkColdFusionStatus 
}

checkColdFusionStatus(){

	url="http://localhost:8500/CFIDE/administrator/index.cfm"
        responsecode=$(curl --write-out %{http_code} --silent --output /dev/null "${url}")
	
	if [ "$responsecode" = "200" ]
        then
	        return 0
        else
        	echo "[$responsecode] Checking server startup status..."
		sleep 5
		checkColdFusionStatus
        fi
}

updateWebroot(){

        echo "Updating webroot to /app"
        xmlstarlet ed -P -S -L -s /Server/Service/Engine/Host -t elem -n ContextHolder -v "" \
                -i //ContextHolder -t attr -n "path" -v "" \
                -i //ContextHolder -t attr -n "docBase" -v "/app" \
                -i //ContextHolder -t attr -n "WorkDir" -v "/opt/coldfusion/cfusion/runtime/conf/Catalina/localhost/tmp" \
                -r //ContextHolder -v Context \
        /opt/coldfusion/cfusion/runtime/conf/server.xml

        echo "Configuring virtual directories"
        xmlstarlet ed -P -S -L -s /Server/Service/Engine/Host/Context -t elem -n ResourceHolder -v "" \
                -r //ResourceHolder -v Resources \
        /opt/coldfusion/cfusion/runtime/conf/server.xml

        xmlstarlet ed -P -S -L -s /Server/Service/Engine/Host/Context/Resources -t elem -n PreResourcesHolder -v "" \
                -i //PreResourcesHolder -t attr -n "base" -v "/opt/coldfusion/cfusion/wwwroot/CFIDE" \
                -i //PreResourcesHolder -t attr -n "className" -v "org.apache.catalina.webresources.DirResourceSet" \
                -i //PreResourcesHolder -t attr -n "webAppMount" -v "/CFIDE" \
                -r //PreResourcesHolder -v PreResources \
        /opt/coldfusion/cfusion/runtime/conf/server.xml

	xmlstarlet ed -P -S -L -s /Server/Service/Engine/Host/Context/Resources -t elem -n PreResourcesHolder -v "" \
                -i //PreResourcesHolder -t attr -n "base" -v "/opt/coldfusion/cfusion/wwwroot/cf_scripts" \
                -i //PreResourcesHolder -t attr -n "className" -v "org.apache.catalina.webresources.DirResourceSet" \
                -i //PreResourcesHolder -t attr -n "webAppMount" -v "/cf_scripts" \
                -r //PreResourcesHolder -v PreResources \
        /opt/coldfusion/cfusion/runtime/conf/server.xml

	xmlstarlet ed -P -S -L -s /Server/Service/Engine/Host/Context/Resources -t elem -n PreResourcesHolder -v "" \
                -i //PreResourcesHolder -t attr -n "base" -v "/opt/coldfusion/cfusion/wwwroot/WEB-INF" \
                -i //PreResourcesHolder -t attr -n "className" -v "org.apache.catalina.webresources.DirResourceSet" \
                -i //PreResourcesHolder -t attr -n "webAppMount" -v "/WEB-INF" \
                -r //PreResourcesHolder -v PreResources \
        /opt/coldfusion/cfusion/runtime/conf/server.xml
	
	# Virtual directory for interal Admin APIs
	xmlstarlet ed -P -S -L -s /Server/Service/Engine/Host/Context/Resources -t elem -n PreResourcesHolder -v "" \
		-i //PreResourcesHolder -t attr -n "base" -v "/opt/startup/coldfusion/" \
                -i //PreResourcesHolder -t attr -n "className" -v "org.apache.catalina.webresources.DirResourceSet" \
                -i //PreResourcesHolder -t attr -n "webAppMount" -v "/ColdFusionDockerStartupScripts" \
                -r //PreResourcesHolder -v PreResources \
        /opt/coldfusion/cfusion/runtime/conf/server.xml

        # Copy files to webroot
        if [ ! -d /app ]; then
		mkdir /app
        fi	

	cp -R /opt/coldfusion/cfusion/wwwroot/crossdomain.xml /app/
        chown -R cfuser /app

}

cleanupTestDirectories(){

	echo "Cleaning up setup directories"
	
	# Remove virtual directory mapping from server.xml
	xmlstarlet ed -P -S -L -d '/Server/Service/Engine/Host/Context/Resources/PreResources[@webAppMount="/ColdFusionDockerStartupScripts"]' /opt/coldfusion/cfusion/runtime/conf/server.xml

	# Delete directory
	rm -rf /opt/startup/coldfusion
}

updatePassword(){

        if [ -z ${password+x} ]; then
                echo "Skipping password updation";
        else
                echo "Updating password";
                awk -F"=" '/password=/{$2="='$password'";print;next}1' /opt/coldfusion/cfusion/lib/password.properties > /opt/coldfusion/cfusion/lib/password.properties.tmp
                mv /opt/coldfusion/cfusion/lib/password.properties.tmp /opt/coldfusion/cfusion/lib/password.properties
                awk -F"=" '/encrypted=/{$2="=false";print;next}1' /opt/coldfusion/cfusion/lib/password.properties > /opt/coldfusion/cfusion/lib/password.properties.tmp
                mv /opt/coldfusion/cfusion/lib/password.properties.tmp /opt/coldfusion/cfusion/lib/password.properties

                chown cfuser /opt/coldfusion/cfusion/lib/password.properties
        fi
}

updateLanguage(){
	if [ -z ${language+x} ]; then
                echo "Skipping language updation";
        else
                echo "Updating language";
		sed -i -- 's/-Duser.language=en/-Duser.language='$language'/g' /opt/coldfusion/cfusion/bin/jvm.config
	fi
}

enableSecureProfile(){

        returnVal=0
        if [ -z ${enableSecureProfile+x} ]; then
                echo "Secure Profile: Disabled"
        else
                if [ $enableSecureProfile = true ]; then

			echo "Attempting to enable secure profile"

                        # Update Password
                        if [ -z ${password+x} ]; then
                                sed -i -- 's/<ADMIN_PASSWORD>/"admin"/g' /opt/startup/coldfusion/enableSecureProfile.cfm
                        else
                                sed -i -- 's/<ADMIN_PASSWORD>/"'$password'"/g' /opt/startup/coldfusion/enableSecureProfile.cfm
                        fi
 
                        curl "http://localhost:8500/ColdFusionDockerStartupScripts/enableSecureProfile.cfm"

                        returnVal=1
                else
                        echo "Secure Profile: Disabled"
                fi
        fi

        return "$returnVal"
}

checkAddonsStatus(){

        url="http://$1:$2/solr"
        responsecode=$(curl --write-out %{http_code} --silent --output /dev/null "${url}")

        if [ "$responsecode" = "302" ]
        then
                return 0
        else
                echo "[$responsecode][$url] Checking addons startup status..."
                sleep 5
                checkAddonsStatus
        fi
}

setupExternalAddons(){

	returnVal=0
        if [ -z ${configureExternalAddons+x} ]; then
                echo "External Addons: Disabled"
        else
                if [ $configureExternalAddons = true ]; then

			echo "Configuring External Addons"

                        # Update Password
                        if [ -z ${password+x} ]; then
                                sed -i -- 's/<ADMIN_PASSWORD>/"admin"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
                        else
                                sed -i -- 's/<ADMIN_PASSWORD>/"'$password'"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
                        fi

			# Update Addons Host
			_addonsHost="localhost"
			if [ -z ${addonsHost+x} ]; then
				sed -i -- 's/<ADDONS_HOST>/"localhost"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			else
				sed -i -- 's/<ADDONS_HOST>/"'$addonsHost'"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
				_addonsHost="$addonsHost"
			fi 
				
			# Update Addons Port
			_addonsPort="8989"
			if [ -z ${addonsPort+x} ]; then
				sed -i -- 's/<ADDONS_PORT>/8989/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			else
				sed -i -- 's/<ADDONS_PORT>/'$addonsPort'/g' /opt/startup/coldfusion/enableExternalAddons.cfm
				_addonsPort="$addonsPort"
			fi

			# Update Addons Username
			if [ -z ${addonsUsername+x} ]; then
				sed -i -- 's/<ADDONS_USERNAME>/"admin"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			else
				sed -i -- 's/<ADDONS_USERNAME>/"'$addonsUsername'"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			fi

			# Update Addons Password
			if [ -z ${addonsPassword+x} ]; then
				sed -i -- 's/<ADDONS_PASSWORD>/"admin"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			else
				sed -i -- 's/<ADDONS_PASSWORD>/"'$addonsPassword'"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			fi

			# Update PDF Service name
			if [ -z ${addonsPDFServiceName+x} ]; then
				sed -i -- 's/<PDF_SERVICE_NAME>/"addonsContainer"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			else
				sed -i -- 's/<PDF_SERVICE_NAME>/"'$addonsPDFServiceName'"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			fi

			# Update PDF SSL
			if [ -z ${addonsPDFSSL+x} ]; then
				sed -i -- 's/<PDF_SSL>/false/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			else
				sed -i -- 's/<PDF_SSL>/'$addonsPDFSSL'/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			fi

			checkAddonsStatus $_addonsHost $_addonsPort

			curl "http://localhost:8500/ColdFusionDockerStartupScripts/enableExternalAddons.cfm"

                        returnVal=1
                else
                        echo "External Addons: Disabled"
                fi
        fi

        return "$returnVal"
}

setupExternalSessions(){

	returnVal=0

        if [ -z ${configureExternalSessions+x} ]; then
                echo "External Session Storage: Disabled"
        else
		if [ $configureExternalSessions = true ]; then

			echo "Configuring external session storage on $externalSessionsHost:$externalSessionsPort"
	
			# Update Password
	                if [ -z ${password+x} ]; then
                		sed -i -- 's/<ADMIN_PASSWORD>/"admin"/g' /opt/startup/coldfusion/enableSessionStorage.cfm
                	else
                		sed -i -- 's/<ADMIN_PASSWORD>/"'$password'"/g' /opt/startup/coldfusion/enableSessionStorage.cfm
        	        fi
	
			if [ -z ${externalSessionsHost+x} ]; then
				sed -i -- 's/<REDIS_HOST>/"localhost"/g' /opt/startup/coldfusion/enableSessionStorage.cfm
				externalSessionsHost="localhost"
			else
				sed -i -- 's/<REDIS_HOST>/"'$externalSessionsHost'"/g' /opt/startup/coldfusion/enableSessionStorage.cfm
			fi

			if [ -z ${externalSessionsPort+x} ]; then
				sed -i -- 's/<REDIS_PORT>/"6379"/g' /opt/startup/coldfusion/enableSessionStorage.cfm
				externalSessionsPort="6379"
                	else
        	                sed -i -- 's/<REDIS_PORT>/"'$externalSessionsPort'"/g' /opt/startup/coldfusion/enableSessionStorage.cfm
			fi		

			if [ -z ${externalSessionsPassword+x} ]; then
				sed -i -- 's/<REDIS_PASSWORD>/""/g' /opt/startup/coldfusion/enableSessionStorage.cfm
                	else
                        	sed -i -- 's/<REDIS_PASSWORD>/"'$externalSessionsPassword'"/g' /opt/startup/coldfusion/enableSessionStorage.cfm
			fi
	
			curl "http://localhost:8500/ColdFusionDockerStartupScripts/enableSessionStorage.cfm"
	
			returnVal=1
		else
			echo "External Session Storage: Disabled"
		fi
	fi

	return "$returnVal"

}

setupSerialNumber(){

	returnVal=0

	# Serial Number
        if [ -z ${serial+x} ]; then
                echo "Serial Key: Not Provided"
        else
                echo "Updating serial key.."
       		sed -i -- 's/^sn=/sn='$serial'/g' /opt/coldfusion/cfusion/lib/license.properties
		returnVal=1 
	fi

	# Previous Serial Number - For Upgrade
	if [ -z ${previousSerial+x} ]; then
                echo "Previous Serial Key: Not Provided"
        else
                echo "Updating previous serial key.."
                sed -i -- 's/^previous_sn=/previous_sn='$previousSerial'/g' /opt/coldfusion/cfusion/lib/license.properties 
                returnVal=1
        fi

        return "$returnVal"
}

importCAR(){

	stat -t -- /data/*.car >/dev/null 2>&1 && returnVal=1 || returnVal=0        

	# Update Password
        if [ -z ${password+x} ]; then
        	sed -i -- 's/<ADMIN_PASSWORD>/"admin"/g' /opt/startup/coldfusion/importCAR.cfm
        else
        	sed -i -- 's/<ADMIN_PASSWORD>/"'$password'"/g' /opt/startup/coldfusion/importCAR.cfm
        fi

	curl "http://localhost:8500/ColdFusionDockerStartupScripts/importCAR.cfm"

	return "$returnVal"
}

invokeCustomCFM(){

        returnVal=0
        if [ -z ${setupScript+x}  ]; then
                echo "Skipping setup script invocation"
        else
                echo "Invoking custom CFM, $setupScript"
                curl "http://localhost:8500/$setupScript"

                returnVal=1

		# Delete setup script if requested
		if [ -z ${setupScriptDelete+x}  ]; then
                	echo "Retaining setupScript in the webroot"
        	else
			if [ $setupScriptDelete = true ]; then
				echo "Deleting setupScript"	
				rm -rf "/app/$setupScript"
			else
				echo "Retaining setupScript in the webroot"
			fi
		fi
        fi

        return "$returnVal"
}


info(){
        /opt/coldfusion/cfusion/bin/cfinfo.sh -version
}

cli(){
	cd /app
        /opt/coldfusion/cfusion/bin/cf.sh "$filename"
}

validateEulaAcceptance(){
	if [ -z ${acceptEULA+x} ] || [ $acceptEULA != "YES" ]; then

                echo "EULA needs to be accepted. Required environment variable, acceptEULA=YES"
                exit 1
        fi
}

help(){
        echo "Supported commands: help, start, info, cli <.cfm>"
	echo "Webroot: /app"
	echo "CAR imports: CAR files present in /data will be automatically imported during startup"
        echo "Required ENV Variables:
		acceptEULA=YES"
	echo "Optional ENV variables: 
		serial=<ColdFusion Serial Key>
		previousSerial=<ColdFusion Previous Serial Key (Upgrade)>
		password=<Password>
		enableSecureProfile=<true/false(default)> 
		configureExternalSessions=<true/false(default)>
		externalSessionsHost=<Redis Host (Default:localhost)>
		externalSessionsPort=<Redis Port (Default:6379)>
		externalSessionsPassword=<Redis Password (Default:Empty)>
		configureExternalAddons=<true/false(default)>
		addonsHost=<Addon Container Host (Default: localhost)>
                addonsPort=<Addon Container Port (Default: 8989)>
		addonsUsername=<Solr username (Default: admin)>
                addonsPassword=<Solr password (Default: admin)>
		addonsPDFServiceName=<PDF Service Name (Default: addonsContainer)>
		addonsPDFSSL=<true/false(default)>
		setupScript=<CFM page to be invoked on startup. Must be present in the webroot, /app>
		setupScriptDelete=<true/false(default) Auto delete setupScript post execution>
		language=<ja/en (Default: en)>"
}

# METHODS END

case "$1" in
        "start")
             	validateEulaAcceptance
		start
                ;;

        info)
                info
                ;;

        cli)
		validateEulaAcceptance
                cli
                ;;

        help)
                help
                ;;

        *)
		validateEulaAcceptance
                cd /opt/coldfusion/cfusion/bin/
                exec "$@"
                ;;

esac

