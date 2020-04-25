package main

import (
        // "flag"
        "fmt"
        "os"
        // "database/sql"
        // _ "github.com/lib/pq"
	"math"
        "regexp"
        "bufio"
        "strconv"
        // "time"
        "strings"
        // "bytes"
)


func checkErr(e error) {
        if e != nil {
                panic(e)
        }
}

// Input from listing:

// # TOTAL NETBLOCK: 70739
// 0.0.0.214/32
// 0.0.4.210/32
// 0.1.226.64/32
// 1.0.115.69/32
// 1.1.1.1/32
// 1.1.221.157/32

// Desired output:

// create voipbl_temp hash:ip family inet hashsize 16384 maxelem 65536
// add voipbl_temp 0.0.0.214
// add voipbl_temp 0.0.4.210
// add voipbl_temp 0.1.226.64
// add voipbl_temp 1.0.115.69
// add voipbl_temp 1.1.1.1
// add voipbl_temp 1.1.221.157
// add voipbl_temp 1.6.0.0
// add voipbl_temp 1.20.141.64
// add voipbl_temp 1.20.141.210
// add voipbl_temp 1.20.141.214

// Note: all the cidr's are exploded out.

func main() {
        hname, err := os.Hostname()
        checkErr(err)
        fmt.Println("Got hostname = ", hname)

        patt := regexp.MustCompile(`([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/([0-9]+)`)
	comment := regexp.MustCompile(`[ 	]*#`)

	args := os.Args[1:]
	arglen := len(args)
	if arglen < 2 {
		fmt.Println("Usage: voipbl-convert <file> <ipset-name> ")
		fmt.Println("Example: voipbl-convert /etc/")
		os.Exit(1)
	}
	fmt.Println(args, arglen)
	vbl_file := args[0]
	ipset_name := args[1]
	fmt.Println("ipset name: ", ipset_name)

	// suck in the voipBL listing file
	fmt.Println("About to open ", vbl_file)
	f1, err := os.Open(vbl_file)
	checkErr(err);
	defer f1.Close()

	// blow out the ipset save/restore formatted file
	ofilename := fmt.Sprintf("%s.t", vbl_file)
	fmt.Println("About to open ", ofilename, " for output!")
	f2, err := os.Create(ofilename)
	checkErr(err);
	defer f2.Close()
	f2w := bufio.NewWriter(f2)
	_, err = f2w.WriteString("create voipbl_temp hash:ip family inet hashsize 16384 maxelem 65536\n")
	checkErr(err);

	scan := bufio.NewScanner(f1)
	for scan.Scan() {
		if scanerr := scan.Err(); scanerr != nil {
			fmt.Println("Scanner is throwing an error! err: ", scanerr)
			os.Exit(2)
		}
		line := scan.Text()
		m0 := comment.MatchString(line)
		if m0 {
			// fmt.Println("Ignoring comment: ", line)
			continue // skip over comments
		}
		// fmt.Println("Line is: ", line)
		m1 := patt.FindAllStringSubmatch(line, -1)
		// fmt.Println("m1: ", m1)
		//  m1[0]:  [0.0.0.214/32 0 0 0 214 32]
		//  m1[0][0]:  0.0.0.214/32
		//  m1[0][1]:  0
		//  m1[0][2]:  0
		//  m1[0][3]:  0
		//  m1[0][4]:  214
		//  m1[0][5]:  32
		// fmt.Println("m1[0]: ", m1[0])
		// fmt.Println("m1[0][0]: ", m1[0][0]) -- the full string
		// fmt.Println("m1[0][1]: ", m1[0][1])
		// fmt.Println("m1[0][2]: ", m1[0][2])
		// fmt.Println("m1[0][2]: ", m1[0][3])
		// fmt.Println("m1[0][2]: ", m1[0][4])
		// fmt.Println("m1[0][2]: ", m1[0][5])
		if m1 == nil {
			fmt.Println("Could not find a match for ip/cidr:  line: ", line)
			continue
		}
		four, err2 := strconv.ParseInt(m1[0][4],10, 64)
		checkErr(err2);
		cidr, err2 := strconv.ParseFloat(m1[0][5], 64)
		checkErr(err2);
		len := int64(math.Pow(2.0,(32.0-cidr)))
		// fmt.Println("len is: ", len, "  four is: ", four, "   cidr is: ", cidr)
// add voipbl_temp 0.1.226.64
		for i:= int64(0); i< len; i++ {
			var oline strings.Builder
			if m1[0][1] == "0" && m1[0][2] == "0" && m1[0][3] == "0" && four == 0 && i == 0 {
				continue; // skip over the 0.0.0.0 entry! ipset will return an error!
			}
			fmt.Fprintf(&oline, "add voipbl_temp %s.%s.%s.%d\n", m1[0][1], m1[0][2],m1[0][3],four+i)
			_, err2 := f2w.WriteString(oline.String())
			checkErr(err2)
		}
	}
	f2w.Flush()
}
