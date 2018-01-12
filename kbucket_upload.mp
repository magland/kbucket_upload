#!/usr/bin/env nodejs

require('dotenv').config({path:__dirname+'/.env'});

var fs = require('fs');
var request = require('request');

var spec={
	processors:[
		{
			name:'kbucket.upload',
			exe_command:__filename+' upload $(arguments)',
			version:0.1,
			inputs:[
				{name:'file',optional:false}
			],
			outputs:[],
			parameters:[
				{name:'force_run',optional:true}
			],
			opts:{
			}
		}
	]
};

function print_spec() {	
	console.log (JSON.stringify(spec,null,4));
	return;
}

var CLP=new CLParams(process.argv);
var arg1=CLP.unnamedParameters[0]||'';
if ((!arg1)||(arg1=='spec')) {
	print_spec();
}
else if (arg1=='upload') {
	handle_upload(CLP.namedParameters,function(err) {
		if (err) {
			console.error(err);
			process.exit(-1);
		}
		else {
			console.log ('Upload successful.');
		}
	});
}
else {
	console.error('Unrecognized processor: '+arg1);
	process.exit(-1);
}

function handle_upload(params,callback) {
	if (!process.env.KBUCKET_AUTH) {
		callback('Environment variable KBUCKET_AUTH not set (use a .env file).');
		return;
	}
	var fname=params.file;
	if (!fname) {
		callback('Missing parameter: file');
		return;
	}
	var size=get_file_size(fname);
	if (!size) {
		callback('Size of file is 0.');
		return;
	}

	var base_url='https://river.simonsfoundation.org';
	var resumable_id=make_random_id(10);
	var url=base_url+'/upload?';
	url+='auth='+process.env.KBUCKET_AUTH;
	url+='&resumableChunkNumber=1';
	url+='&resumableChunkSize='+size;
	url+='&resumableCurrentChunkSize='+size;
	url+='&resumableTotalSize='+size;
	url+='&resumableType=';
	url+='&resumableIdentifier='+resumable_id;
	url+='&resumableFilename=dummy.dat';
	url+='&resumableRelativePath=dummy.dat';
	url+='&resumableTotalChunks=1';

	var url2=base_url+'/upload?';
	url2+='resumableIdentifier='+resumable_id;
	url2+='&resumableFileName=dummy.dat';
	url2+='&resumableTotalSize='+size;
	url2+='&resumableDone=true';

	console.log ('Uploading file...');
	upload_file(url,fname,function(err) {
		if (err) {
			callback('Error uploading file content: '+err);
			return;
		}
		console.log ('Finalizing upload...');
		post_data(url2,'',function(err2,response_body) {
			if (err2) {
				callback('Error finalizing upload: '+err2);
				return;
			}
			var obj=try_parse_json(response_body);
			if (!obj) {
				console.log (response_body);
				callback('Error parsing JSON response');
				return;
			}
			if (!obj.prv) {
				callback('Response does not have a prv field.');
				return;
			}
			if (obj.prv.original_size!=get_file_size(fname)) {
				callback('Incorrect size in returned prv file');
				return;
			}
			console.log('Uploaded file with sha1='+obj.prv.original_checksum+' and size='+obj.prv.original_size);
			callback(null);
		});
	});
}

function get_file_size(fname) {
	try {
		var stat=require('fs').statSync(fname);
		return stat.size;
	}
	catch(err) {
		return null;
	}
}

function try_parse_json(str) {
	try {
		return JSON.parse(str);
	}
	catch(err) {
		return null;
	}
}

function make_random_id(num_chars)
{
    var text = "";
    var possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

    for( var i=0; i < num_chars; i++ )
        text += possible.charAt(Math.floor(Math.random() * possible.length));

    return text;
}

function upload_file(url,fname,callback) {
	/*
	var parts=require('url').parse(url);

    var obj={
    	hostname:parts.hostname,
    	port:443,
    	method:'POST',
    	path:parts.path
    };
	var REQ=require('https').request(obj,function(RES) {
		console.log('RES.');
		//console.log(RES);
		RES.on('data',function(dd) {
			console.log('data');
			console.log(dd);
		});
		RES.on('end', function () {
			console.log('end');
			callback(null);
		});
	});

	REQ.on('error', function (err) {
		console.log('error');
		callback('Error in upload: '+err);
	});

	var rs = require('fs').createReadStream(fname);
	rs.pipe(REQ);
	*/

	var rs = require('fs').createReadStream(fname);
	var ws = request.post(url);

	ws.on('end', function () {
		callback(null);
	});

	ws.on('error', function (err) {
		callback('Error in upload: '+err);
	});

	rs.pipe(ws);
}

function post_data(url,body,callback) {
	request.post({
	  headers: {},
	  url:     url,
	  body:    body
	}, function(error, response, body2){
		if (error) {
			callback(error.message);
			return;
		}
		callback(null,body2);
	});
}

function CLParams(argv) {
	this.unnamedParameters=[];
	this.namedParameters={};

	var args=argv.slice(2);
	for (var i=0; i<args.length; i++) {
		var arg0=args[i];
		if (arg0.indexOf('--')===0) {
			arg0=arg0.slice(2);
			var ind=arg0.indexOf('=');
			if (ind>=0) {
				this.namedParameters[arg0.slice(0,ind)]=arg0.slice(ind+1);
			}
			else {
				//this.namedParameters[arg0]=args[i+1]||'';
				//i++;
				this.namedParameters[arg0]='';
			}
		}
		else if (arg0.indexOf('-')===0) {
			arg0=arg0.slice(1);
			this.namedParameters[arg0]='';
		}
		else {
			this.unnamedParameters.push(arg0);
		}
	}
};
