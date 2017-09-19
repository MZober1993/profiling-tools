#!/usr/bin/env bash

# move this shell-script in the directory of your root - pom.xml and run it to export the dependency-graph in a neo4j-db
# configure your neo4j-connection in the neo4j_connection file (run /bin/cypher-shell against your neo4j-db)

function prepare_dependencies(){
    mvn dependency:tree > tree

    echo "extract data from maven dependency-tree"
    sed -i "s/\[INFO\]//g" tree

    sed -i 's/\ --- maven-dependency-plugin:2.8:tree (default-cli) @ //g' tree
    sed -i 's/\ ---//g' tree

    grep -v " |" tree | grep -v "  " | grep -v "\-\-" | grep -v "Build" | grep -v "Reactor" | grep -v "Scan" | grep -v "Total" | grep -v "Finish" | grep -v "Final" | grep -v "SUCCESS" | grep -e ":" > dependencies
    sed -i 's/\n\n//g' dependencies
    sed -i 's/:compile//g' dependencies
    sed -i 's/:provided//g' dependencies
    sed -i 's/:test//g' dependencies
}

function extract_mvn_name(){
    GROUP=`echo $1 | sed 's/\(:.*$\)//g'`
    VERS=`echo $1 | sed 's/\(^.*:\)//g'`
    ARTF=`echo $1 | sed "s/$GROUP://g" | sed "s/:$VERS//g"`
    echo "{group:'$GROUP',artifact:'$ARTF',version:'$VERS'}"
}

function clean_all(){
    echo "delete tree, dependency and import.cyp file"
    rm tree && rm dependencies && rm import.cyp
}

prepare_dependencies
echo "create import.cyp"
echo "//import-script for the project-dependency-graph" > import.cyp
echo "match (n) detach delete n;" > import.cyp
echo "write matching queries from dependency-tree"
while read line
 do
    if [[ $line == *"- "* ]]; then
        DEP=`echo "$line" | sed 's/+//g' | sed 's/\- //g'`
        DEPPROBS=$(extract_mvn_name $DEP)
        printf "Merge (n:Dependency %s);\n" "$DEPPROBS" >> import.cyp
        printf "Match (n:Project %s),(m:Dependency %s) Create unique (n)-[:USES]->(m);\n" "$PROJPROBS" "$DEPPROBS" >> import.cyp
    else
        echo "export dependencies from project: $line"
        PROJPROBS=$(extract_mvn_name $line)
        printf "Merge (n:Project:Dependency %s);\n" "$PROJPROBS" >> import.cyp
        if ! [ -v ROOT ]; then
            ROOT="$line"
        else
            echo "detect submodule $PROJ of $ROOT"
            ROOTPROBS=$(extract_mvn_name $ROOT)
            printf "Match (n:Project %s),(m:Project %s) Create unique (n)-[:CHILDREN]->(m);\n" "$ROOTPROBS" "$PROJPROBS" >> import.cyp
        fi
    fi
 done < dependencies

echo "import into neo4j-db"
cat ./import.cyp | `cat neo4j_connection`
clean_all