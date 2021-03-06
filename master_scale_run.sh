#!/bin/bash

#----------- client list ------------
clients=( $2 )
threads=$3
blocksize=( $4 )

#clients=( wl21 wl22 wl23 wl24  )
#----------- run params -------------

volume_size=488G
write_data=3000g
read_data=1000g
interval=3
vol_num=128

debug_verbose="false"
raceMQvalue="0"
comp_ratio=( "1.3" "1.7" "2.3" "3.5" "11" )
#comp_ratio=( "2.3" "3.5" "11" )
#comp_ratio=( "3.5" )
#------ test defenitions -----
WRITE="write_test_"
READ="read_test_"


if [[ $threads == "" ]] ; 
then
    threads=16
fi
if [[ ${#blocksize[@]} -eq 0 ]]; then
    #blocksize=( "1m" "512k" "256k" "128k" "64k" "32k" "16k" "8k" "4k" )
    blocksize=( "16k" "8k" "4k" )
fi

#-------------  delete old clients
echo "Removing Existing hosts : "$(ssh -p 26 $1 lshost -nohdr | awk '{print $2}' | tr "\n" "," )
ssh $1 -p 26 "i=\"0\"; while [ 1 -lt \`lshost|wc -l\` ]; do svctask rmhost -force \$i; i=\$[\$i+1]; done"
#-------------  add clients
echo "Creating hosts"
totalFC=0
for c in ${clients[@]}
do
    wwpn=`ssh $c /usr/global/scripts/qla_show_wwpn.sh | grep Up | awk '{print $1}' | tr "\n" ":"| sed -e 's|\:$||g'`
    wwpnHostCount=`ssh $c /usr/global/scripts/qla_show_wwpn.sh | grep -c Up `
    totalFC=$((  totalFC + $wwpnHostCount ))
    if [[ $debug_verbose == "true" ]]; then
        echo "Creating host $c on $1 adding wwpn $wwpn"
        echo "commmand : ssh $1 -p 26 svctask mkhost -fcwwpn $wwpn  -force -iogrp io_grp0:io_grp1:io_grp2:io_grp3 -name $c -type generic 2>/dev/null"
        ssh $1 -p 26 svctask mkhost -fcwwpn $wwpn  -force -iogrp io_grp0:io_grp1:io_grp2:io_grp3 -name $c -type generic 2>/dev/null
    else 
        echo "Creating host $c on $1"
        #ssh $1 -p 26 svctask mkhost -fcwwpn $wwpn  -force -iogrp io_grp0:io_grp1:io_grp2:io_grp3 -name $c -type generic 2&1>/dev/null
        ssh $1 -p 26 svctask mkhost -fcwwpn $wwpn  -force -iogrp io_grp0:io_grp1:io_grp2:io_grp3 -name $c -type generic >/dev/null
        #ssh $1 -p 26 svctask mkhost -fcwwpn $wwpn -force -iogrp 0:1 -name $c -type generic 2&1>/dev/null
    fi
done
#------------ clear log
		echo "Cleaning logs"
		ssh $1 -p 26 svctask clearerrlog -force
#--- create results directory
svcVersion=$(ssh $1 -p 26 cat /compass/version )
svcBuild=$(ssh $1 -p 26 cat /compass/vrmf )
results_path="vdbench_benchmark_test"
echo -e "===[ global test parameters ]=============================================================
Storage name          : [ $1 ]
SVC Version           : [ $svcBuild ]
SVC Build             : [ $svcVersion ]
Threads per lun       : [ $threads ]
Test Block Size       : [ ${blocksize[@]} ]
\n===[ Data Set ] =============================================================================
Total Volumes         : [ $vol_num ]
Volume size           : [ $volume_size ]
Total write data      : [ $write_data ]
Total read data       : [ $read_data ]
\n"

time_stamp=$(date +%y%m%d_%H%M%S)
rpath="$results_path/$svcBuild/$svcVersion/$time_stamp"
storageInfoJson="$results_path/$svcBuild/$svcVersion/$time_stamp/storageInfo.json"
if [ ! -d "$rpath" ] ;then
	mkdir -p $rpath
fi
echo "
{
 	\"ResultsType\":          \"DEV\",
        \"testType\":             \"IOZONE\",
        \"stand\":                \"$1\",
        \"SVC_Version\":          \"$svcBuild\",
        \"SVCBuilds\":            \"$svcVersion\",
        \"backend\":              \"$backendName\",
        \"diskType\":             \"NONE\",
        \"noOfDisks\":            \"8\",
        \"totalDisks\":           \"1.2\",
        \"Raid\":                 \"\",
        \"testmode\":             \"CMP\",
        \"vdiskCount\":           \"$vol_num\",
        \"vdiskSize\":            \"$volume_size\",
        \"coleto\":               \"\",
        \"coleto_level\":         \"2\",
        \"ClientMgmt\":           \"`hostname`\",
        \"Clients\":              \"${clients[@]}\",
        \"ClientsNum\":           \"${#clients[@]}\",
        \"ThreadsPerClient\": 	  \"$threads\",
        \"LunPerClient\":         \"$(( $vol_num / ${#clients[@]} ))\",
        \"FCperClient\":          \"$(( $totalFC / ${#clients[@]} ))\",

" > $storageInfoJson

for bs in ${blocksize[@]}; do
#for bs in 1m 512k 256k 128k 64k 32k 16k 8k 4k ; do

#rpath="$results_path/$time_stamp/$svcBuild/$svcVersion/$bs"
rpath="$results_path/$svcBuild/$svcVersion/$time_stamp/$bs"
test_results="$rpath/test_results"
test_files="$rpath/test_files"
test_data="$rpath/output_data"
#----------------- create directory structure 
if [ ! -d "$rpath" ] ; then
    mkdir -p $test_results
    mkdir -p $test_files
    mkdir -p $test_data
fi

#----------------- do a loop with all compression ratios
for CP in ${comp_ratio[@]} ; do
#for CP in {1.3,1.7,2.3,3.5,11}; do

output_file=$test_results/"out_$CP"
disk_file=$CP"_disk_list"
write_test_file=$test_files/$CP"_write"
read_test_file=$test_files/$CP"_read"
disk_list=$test_files/$disk_file
test_info="vdbench_benchmark_information_$CP.log"

echo -e "===[ test parameters ]===================================================================
Compration ratio      : [ $CP ]
Test Block Size       : [ $bs ]
\n===[ directory stracture ]=====================================================================
test results          : [ $test_results ]
test files directory  : [ $test_files ]
output test data      : [ $test_data ]
output file           : [ $output_file ]
verbose output        : [ $debug_verbose ]
" | tee -a  $rpath/$test_info


	mdiskid=`ssh $1 -p 26 ""lsmdiskgrp |grep -v id | sed -r 's/^[^0-9]*([0-9]+).*$/\1/'""`
	echo -e "Removing mdiskgrp id : $mdiskid from $1" | tee -a $rpath/$test_info
	ssh $1 -p 26 svctask rmmdiskgrp -force $mdiskid

	hardwareType=`ssh $1 -p 26 sainfo lshardware | grep hardware | awk '{print \$2}'`
	ssh $1 -p 26 "ls /home/mk_arrays_master" 2>&- >/dev/null
	if [[ $? == 0 ]]; then
#         ssh -p 26 $1 /home/mk_arrays_master fc raid5 sas_hdd 238 8 32 128 400 COMPRESSED NOFMT AUTOEXP >/dev/null
        array_drive=8
        number_of_drive=$(ssh -p 26 $1 lsdrive -nohdr | wc -l)
        number_of_mdisk_group=$(( $number_of_drive / $array_drive ))
	    vol_size=488
      	if [[ $debug_verbose =~ "true" ]]; then
	    echo "Running with FAB configuration with ouput"
            ssh -p 26 $1 /home/mk_arrays_master fc raid10 sas_hdd $number_of_drive $array_drive $number_of_mdisk_group $vol_num $vol_size COMPRESSED NOFMT NOSCRUB | tee -a  $rpath/$test_info
        else 
	    echo "Creating volumes on $1"
		                              #fc, raid5, sas_hdd, 216, 8, 27, 64, 10, NOSCRUB, NOFMT, COMPRESSED, NOCACHE
            ssh -p 26 $1 /home/mk_arrays_master fc raid10 sas_hdd $number_of_drive $array_drive $number_of_mdisk_group $vol_num $vol_size COMPRESSED NOFMT NOSCRUB &> $rpath/$test_info
        fi
	else
		echo "Running with BFN configuration"
		#echo "ssh $1 -p 26 /home/mk_vdisks fc 1 $vol_num 409600 0 NOFMT COMPRESSED AUTOEXP >/dev/null"
		ssh $1 -p 26 /home/mk_vdisks fc 1 $vol_num 495600 0 NOFMT COMPRESSED AUTOEXP >> $rpath/$test_info
	fi
	sleep 60


#-------------  rescan multipath on clients
#-------------  rescan multipath on clients
 
    echo -e "++ rescan on clients +++++++++++++++++++++++++++++ " | tee -a $rpath/$test_info
    for client in "${clients[@]}"; do
        echo -e "$client \c " | tee -a $rpath/$test_info
        ssh $client /usr/global/scripts/rescan_all.sh >> $rpath/$test_info
        echo "vdisks : [ " $(ssh $client multipath -l | grep -c mpath)" ]"| tee -a $rpath/$test_info
    done



if [ $raceMQvalue -eq "0" ] ; then 
echo " \"RaceMQVersion\":        \"$(ssh -p 26 $stg /data/race/rtc_racemqd -v | grep race | awk '{print $2}' | sed -e 's/v//g')\",
       \"MultiRace\":            \"$(ssh -p 26 $stg ps -efL | grep race | awk '$10 ~ /racemqAd/ { rAd++ } 
																		$10 ~ /racemqBd/ { rBd++ } 
																		$10 ~ /rtc_racemqd/ { rtc_rqd++ } 
				END { \
				     
 					if ( rAd > 2 && rBd > 2  ) { print "2" } \
					else if ( rAd > 2  && rBd < 2 ) { print "1" } \
					else if ( rtc_rqd > 12 ) { print "1" } \
					else if ( rAd < 1 && rBd < 1 && rtc_rqd < 1 ) { print "noRaceRuning" } 
				}')\",
'\",
">>$storageInfoJson
   raceMQvalue="1"
fi 
#-------------  create map of availiable disks
	echo " " > $disk_list 
	for client in "${clients[@]}"; do
		count=1
        for dev in `ssh $client multipath -l|grep "2145" | awk '{print \$1}'`; do
            device="/dev/mapper/$dev"
            if [[ $debug_verbose =~ "true" ]]; then
                echo "vdbench sd output: sd=$client.$count,hd=$client,lun=$device,openflags=o_direct,size=$volume_size,threads=$threads"
                echo "sd=$client.$count,hd=$client,lun=$device,openflags=o_direct,size=$volume_size,threads=$threads" >> $disk_list
                count=$(( count+1  ))
            else
                echo "sd=$client.$count,hd=$client,lun=$device,openflags=o_direct,size=$volume_size,threads=$threads" >> $disk_list
                count=$(( count+1  ))
            fi
		done;
	done

#write  
	echo "
compratio=$CP
messagescan=no
	
" > $write_test_file
	for client in "${clients[@]}"; do
		echo "hd=$client,system=$client.eng.rtca,shell=ssh,vdbench=/root/vdbench,user=root" >> $write_test_file
	done
	echo "
include=$disk_list

wd=wd1,sd=*,xfersize=$bs,rdpct=0,rhpct=0,seekpct=0
rd=run1,wd=wd1,iorate=max,elapsed=24h,maxdata=$write_data,warmup=360,interval=$interval
" >> $write_test_file
    if [[ $debug_verbose == 'true' ]]; then
	    ./vdbench -c -f $write_test_file  -o $test_data/output_$CP | tee -a $output_file
    else
        echo "log view : $output_file"
	    ./vdbench -c -f $write_test_file  -o $test_data/output_$CP >> $output_file
    fi

#-------- take comp ratios
	./graphite_rtc_cr.py $1 | tee -a $output_file
	sleep 120
#read
        echo "
compratio=$CP
messagescan=no
" > $read_test_file
        for client in "${clients[@]}"; do
                echo "hd=$client,system=$client.eng.rtca,shell=ssh,vdbench=/root/vdbench,user=root" >> $read_test_file
        done
        echo "
include=$disk_list

wd=wd1,sd=*,xfersize=$bs,rdpct=100,rhpct=0,seekpct=0
rd=run1,wd=wd1,iorate=max,elapsed=24h,maxdata=$read_data,warmup=360,interval=$interval
" >> $read_test_file
    if [[ $debug_verbose == 'true' ]];then
    	./vdbench -c -f $read_test_file -o $test_data/output_$CP | tee -a $output_file
    else
        echo "log view : $output_file"
	    ./vdbench -c -f $read_test_file -o $test_data/output_$CP >> $output_file
    fi

done

#./get_vdbench_res.pl --stand=$1 -d -path $test_results
done 
