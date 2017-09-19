#!/usr/bin/env bash

# move this shell-script in the directory of your target and run it to export the method-graph in a neo4j-db
# configure your neo4j-connection in the neo4j_connection file (run /bin/cypher-shell against your neo4j-db)

function prepare_method_graph(){
    rm graph
    touch graph
    find $1 -name \*.class |
        sed s/\\.class$// |
        while read x
        do
            echo "class $x" >> graph
            javap -v $x | grep -e "Methodref" >> graph
        done

    sed -i 's/\(^.*\/\/ \)//g' graph
    sed -i '/java\/lang\/Object."<init>":()V/d' graph
}

function extract_class_name(){
    NAME=`echo "$1" | sed 's/\(^.*\/\)//g'`
    PACKAGE=`echo $1 | sed "s/$NAME//g"`
    echo "{name:'$NAME', package:'$PACKAGE'}"
}

function extract_method_name(){
    PAR=`echo "$1" | sed 's/\(^.*:\)//g'`
    MET=`echo "$1" | sed 's/\(:.*$\)//g' | sed 's/\(^.*\/\)//g'`
    echo "{name:'$MET',params:'$PAR'}"
}

function clean_all(){
    echo "delete graph and import_methods.cyp file"
    rm graph && rm import_methods.cyp
}

prepare_method_graph
echo "//import the method-graph" > import_methods.cyp

while read line
 do
    if [[ $line == *"class "* ]]; then
        echo "detect class: $line"
        CLASS=`echo "$line" | sed 's/class .\/target\/classes\///g' | sed 's/class .\/target\/test-classes\///g'`
        CLASSPROBS=$(extract_class_name $CLASS)
        printf "Merge (n:Class %s);\n" "$CLASSPROBS" >> import_methods.cyp
    else
        METHPROBS=$(extract_method_name $line)
        USER=`echo "$line" | sed 's/\(:.*$\)//g' | sed 's/\(\..*\)//g'`
        USERPROBS=$(extract_class_name $USER)

        echo "detect method call $MET from: $USER"
        printf "Merge (n:Class %s);\n" "$USERPROBS" >> import_methods.cyp
        printf "Match (n:Class %s), (m:Class %s) Create unique (n)<-[:METHOD_CALL %s]-(m);\n" "$CLASSPROBS" "$USERPROBS" "$METHPROBS" >> import_methods.cyp
    fi
 done < graph

printf "match (n:Class) where n.package=~'.*java.*' SET n:Java;\n" >> import_methods.cyp
printf "match (n:Class) where n.name=~'.*Test.*' or n.name=~'.*Assert.*' or n.name=~'.*Matcher.*' or n.package=~'.*Mockito.*' or n.package=~'.*test.*' SET n:Test;\n" >> import_methods.cyp
printf "match (n:Class) where not (n:Java or n:Test) set n:Prod;\n" >> import_methods.cyp
printf "match (n:Prod) where n.name=~'.*Repository.*' SET n:Repository;\n" >> import_methods.cyp
printf "match (n:Prod) where n.name=~'.*Controller.*' SET n:Controller;\n" >> import_methods.cyp

echo "import into neo4j-db"
cat ./import_methods.cyp | `cat neo4j_connection`

clean_all