/******************************************************************************
 *
 * 
 *
 *
 * Copyright (C) 1997-2002 by Dimitri van Heesch.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation under the terms of the GNU General Public License is hereby 
 * granted. No representations are made about the suitability of this software 
 * for any purpose. It is provided "as is" without express or implied warranty.
 * See the GNU General Public License for more details.
 *
 * Documents produced by Doxygen are derivative works derived from the
 * input used in their production; they are not affected by this license.
 *
 */

%{

#include <qfile.h>
#include <qcstring.h>
#include <qstack.h>
#include <qdict.h>

#include "doctokenizer.h"
#include "cmdmapper.h"
#include "config.h"
#include "message.h"

#define YY_NEVER_INTERACTIVE 1
  
//--------------------------------------------------------------------------

static int g_commentState;
TokenInfo *g_token = 0;
static int g_inputPos = 0;
static const char *g_inputString;
static QCString g_fileName;

struct DocLexerContext
{
  TokenInfo *token;
  int rule;
  int inputPos;
  const char *inputString;
  YY_BUFFER_STATE state;
};

static QStack<DocLexerContext> g_lexerStack;

//--------------------------------------------------------------------------

void doctokenizerYYpushContext()
{
  DocLexerContext *ctx = new DocLexerContext;
  ctx->rule = YY_START;
  ctx->token = g_token;
  ctx->inputPos = g_inputPos;
  ctx->inputString = g_inputString;
  ctx->state = YY_CURRENT_BUFFER;
  g_lexerStack.push(ctx);
  yy_switch_to_buffer(yy_create_buffer(doctokenizerYYin, YY_BUF_SIZE));
}

bool doctokenizerYYpopContext()
{
  if (g_lexerStack.isEmpty()) return FALSE;
  DocLexerContext *ctx = g_lexerStack.pop();
  g_inputPos = ctx->inputPos;
  g_inputString = ctx->inputString;
  yy_delete_buffer(YY_CURRENT_BUFFER);
  yy_switch_to_buffer(ctx->state);
  BEGIN(ctx->rule);
  delete ctx;
  return TRUE;
}


//--------------------------------------------------------------------------

const char *tokToString(int token)
{
  switch (token)
  {
    case 0:              return "TK_EOF";
    case TK_WORD:        return "TK_WORD";
    case TK_LNKWORD:     return "TK_LNKWORD";
    case TK_WHITESPACE:  return "TK_WHITESPACE";
    case TK_LISTITEM:    return "TK_LISTITEM";
    case TK_ENDLIST:     return "TK_ENDLIST";
    case TK_COMMAND:     return "TK_COMMAND";
    case TK_HTMLTAG:     return "TK_HTMLTAG";
    case TK_SYMBOL:      return "TK_SYMBOL";
    case TK_NEWPARA:     return "TK_NEWPARA";
    case TK_RCSTAG:      return "TK_RCSTAG";
    case TK_URL:         return "TK_URL";
  }
  return "ERROR";
}

static int computeIndent(const char *str,int length)
{
  int i;
  int indent=0;
  int tabSize=Config_getInt("TAB_SIZE");
  for (i=0;i<length;i++)
  {
    if (str[i]=='\t')
    {
      indent+=tabSize - (indent%tabSize);
    }
    else if (str[i]=='\n')
    {
      indent=0;
    }
    else
    {
      indent++;
    }
  }
  return indent;
}

/*! converts input string \a opt into a list of Options. Each
 *  option is a name, value pair. The result is stored in g_token->options
 */
static void parseOptions(const QCString &opt)
{
  //printf("parseOptions(%s)\n",opt.data());
  QCString options=opt;
  g_token->options.clear();
  int len = options.length();
  char c;
  int i=0,startName,endName,startOption,endOption;
  while (i<len)
  {
    c=options.at(i);
    // skip spaces
    while (i<len && c==' ') { c=options.at(++i); }
    startName=i;
    // search for end of name
    while (i<len && c!=' ' && c!='=') { c=options.at(++i); }
    endName=i;
    Option *opt = new Option;
    opt->name  = options.mid(startName,endName-startName).lower(); 
    // skip spaces
    while (i<len && c==' ') { c=options.at(++i); } 
    if (options.at(i)=='=') // option has value
    {
      i++;
      // skip spaces
      while (i<len && c==' ') { c=options.at(++i); } 
      if (options.at(i)=='\'') // option '...'
      {
	i++;
	startOption=i;
	// search for matching quote 
        while (i<len && c!='\'') { c=options.at(++i); } 
	endOption=i;
	i++;
      }
      else if (options.at(i)=='"') // option "..."
      {
	i++;
	startOption=i;
	// search for matching quote 
        while (i<len && c!='"') { c=options.at(++i); } 
	endOption=i;
	i++;
      }
      else // value without any quotes
      {
	startOption=i;
	// search for separator
        while (i<len && c!=' ') { c=options.at(++i); } 
	endOption=i;
	i++;
      }
      opt->value  = options.mid(startOption,endOption-startOption); 
    }
    else // start next option
    {
    }
    //printf("=====> Adding option name=<%s> value=<%s>\n",
    //    opt->name.data(),opt->value.data());
    g_token->options.append(opt);
  }
}

//--------------------------------------------------------------------------

#undef  YY_INPUT
#define YY_INPUT(buf,result,max_size) result=yyread(buf,max_size);

static int yyread(char *buf,int max_size)
{
  int c=0;
  const char *src=g_inputString+g_inputPos;
  while ( c < max_size && *src ) *buf++ = *src++, c++;
  g_inputPos+=c;
  return c;
}

//--------------------------------------------------------------------------

%}

CMD   ("\\"|"@")
WS    [ \t\r\n]
NONWS [^ \t\r\n]
BLANK [ \t\r]
ID    [a-z_A-Z][a-z_A-Z0-9]*
OPTSTARS ("//"{BLANK}*)?"*"*{BLANK}*
LISTITEM {BLANK}*{OPTSTARS}"-"("#")?{WS}
ENDLIST  {BLANK}*{OPTSTARS}"."{BLANK}*\n
ATTRIB   {ID}("="(("\""[^\"]*"\"")|("'"[^\']*"'")|[^ \t\r\n'"><]+))?
URLCHAR   [a-z_A-Z0-9\!\~\:\;\'\$\?\@\&\%\#\.\-\+\/\=]
URLMASK   (([a-z_A-Z][^\>\"\n]*{URLCHAR})|({URLCHAR}+))([({]{URLCHAR}*[)}])?
FILESCHAR [a-z_A-Z0-9\\:\\\/\-\+]
FILEECHAR [a-z_A-Z0-9\-\+]
FILEMASK  {FILESCHAR}*{FILEECHAR}+("."{FILESCHAR}*{FILEECHAR}+)*
LINKMASK  [^ \t\n\r\\@<&$]+("("[^\n)]*")")?({BLANK}*("const"|"volatile"))? 
SPCMD1    {CMD}[a-z_A-Z0-9]+ 
SPCMD2    {CMD}[\\@<>&$#%~]
SPCMD3    {CMD}form#[0-9]+
TEMPCHAR  [a-z_A-Z0-9,: \t\*\&]
FUNCCHAR  [a-z_A-Z0-9,:\<\> \t\*\&]
SCOPESEP  "::"|"#"|"."
SCOPEPRE  {ID}("<"{TEMPCHAR}*">")?{SCOPESEP}
SCOPEMASK {SCOPEPRE}*(~)?{ID}
FUNCARG   "("{FUNCCHAR}*")"
OPNEW     {BLANK}+"new"({BLANK}*"[]")?
OPDEL     {BLANK}+"delete"({BLANK}*"[]")?
OPNORM    {OPNEW}|{OPDEL}|"+"|"-"|"*"|"/"|"%"|"^"|"&"|"|"|"~"|"!"|"="|"<"|">"|"+="|"-="|"*="|"/="|"%="|"^="|"&="|"|="|"<<"|">>"|"<<="|">>="|"=="|"!="|"<="|">="|"&&"|"||"|"++"|"--"|","|"->*"|"->"|"[]"|"()"
OPCAST    {BLANK}+[^(\r\n.,]+
OPMASK    ({BLANK}*{OPNORM}({FUNCARG}?))|({OPCAST}{FUNCARG})
LNKWORD1  {SCOPEMASK}({FUNCARG}({BLANK}*("const"|"volatile"))?)?
LNKWORD2  {SCOPEPRE}*"operator"{OPMASK}
WORD1     [^ \t\n\r\\@<>&$#,.]+ 
WORD2     "."|","
WORD1NQ   [^ \t\n\r\\@<>&$#,."]+ 
WORD2NQ   "."|","
HTMLTAG   "<"(("/")?){ID}({BLANK}+{ATTRIB})*">" 

%option noyywrap
%option yylineno

%x St_Para
%x St_Comment
%x St_Title
%x St_TitleN
%x St_TitleQ
%x St_TitleA
%x St_TitleV
%x St_Code
%x St_HtmlOnly
%x St_LatexOnly
%x St_Verbatim
%x St_Param
%x St_XRefItem
%x St_File
%x St_Pattern
%x St_Link
%x St_Ref
%x St_Ref2
%x St_IntRef

%%
<St_Para>\r               /* skip carriage return */
<St_Para>^{LISTITEM}      { /* list item */ 
                         QCString text=yytext;
			 int dashPos = text.findRev('-');
			 g_token->isEnumList = text.at(dashPos+1)=='#';
			 g_token->indent     = computeIndent(yytext,dashPos);
                         return TK_LISTITEM;
                       }
<St_Para>{BLANK}*\n{LISTITEM}     { /* list item on next line */ 
                         QCString text=yytext;
			 text=text.right(text.length()-text.find('\n')-1);
			 int dashPos = text.findRev('-');
			 g_token->isEnumList = text.at(dashPos+1)=='#';
			 g_token->indent     = computeIndent(text,dashPos);
                         return TK_LISTITEM;
                       }
<St_Para>^{ENDLIST}       { /* end list */ 
                         int dotPos = QCString(yytext).findRev('.');
			 g_token->indent     = computeIndent(yytext,dotPos);
                         return TK_ENDLIST;
                       }
<St_Para>{BLANK}*\n{ENDLIST}      { /* end list on next line */ 
                         QCString text=yytext;
			 text=text.right(text.length()-text.find('\n')-1);
                         int dotPos = text.findRev('.');
			 g_token->indent     = computeIndent(text,dotPos);
                         return TK_ENDLIST;
                       }
<St_Para>"{"{BLANK}*"@link" {
  			 g_token->name = "javalink";
			 return TK_COMMAND;
  		       }
<St_Para>{SPCMD3}      {
  			 g_token->name = "form";
			 bool ok;
			 g_token->id = QCString(yytext).right(yyleng-6).toInt(&ok);
			 ASSERT(ok);
			 return TK_COMMAND;
  		       }
<St_Para>{SPCMD1}      |
<St_Para>{SPCMD2}      { /* special command */
                         g_token->name = yytext+1;
                         return TK_COMMAND;
  		       }
<St_Para>("http:"|"https:"|"ftp:"|"file:"|"news:"){URLMASK} {
                         g_token->name=yytext;
			 return TK_URL;
                       }
<St_Para>[a-z_A-Z0-9.-]+"@"[a-z_A-Z0-9.-]+ {
                         g_token->name=yytext;
			 return TK_URL;
                       }
<St_Para>"$"{ID}":"[^\n$]+"$" { /* RCS tag */
                         QCString tagName(yytext+1);
			 int i=tagName.find(':');
  			 g_token->name = tagName.left(i);
			 g_token->text = tagName.mid(i+1,tagName.length()-i-2);
			 return TK_RCSTAG;
  		       }
<St_Para,St_HtmlOnly>"$("{ID}")"   { /* environment variable */
                         QCString name = &yytext[2];
			 name = name.left(name.length()-1);
			 QCString value = getenv(name);
			 for (int i=value.length()-1;i>=0;i--) unput(value.at(i));
                       }
<St_Para>{HTMLTAG}     { /* html tag */ 
                         g_token->name = yytext;
                         int startNamePos=1;
                         if (g_token->name.at(1)=='/') startNamePos++;
                         int optSep = g_token->name.find(' ');
                         if (optSep!=-1) // tag has one or more options
                         {
                           parseOptions(g_token->name.mid(optSep+1,g_token->name.length()-optSep-2));
                           g_token->name=g_token->name.mid(startNamePos,optSep-1).lower();
                         }
                         else // tag without options, strip brackets
                         {
                           g_token->name=g_token->name.mid(startNamePos,g_token->name.length()-startNamePos-1).lower();
                         }
			 g_token->endTag = startNamePos==2;
                         return TK_HTMLTAG;
                       }
<St_Para>"&"{ID}";"       { /* special symbol */ 
                         g_token->name = yytext;
                         return TK_SYMBOL;
                       }
<St_Para>{LNKWORD1}    |
<St_Para>{LNKWORD2}    {
                         g_token->name = yytext;
                         return TK_LNKWORD;
  		       }
<St_Para>{WORD1}       |
<St_Para>{WORD2}       { /* function call */ 
                         g_token->name = yytext;
                         return TK_WORD;

			 /* the following is dummy code to please the 
			  * compiler, removing this results in a warning 
			  * on my machine 
			  */ 
			 goto find_rule;
                       }
<St_Para>{BLANK}+      |
<St_Para>{BLANK}*\n{BLANK}* { /* white space */ 
                         g_token->chars=yytext;
                         return TK_WHITESPACE;
                       }
<St_Para>({BLANK}*\n)+{BLANK}*\n {
                         /* start of a new paragraph */
  		         return TK_NEWPARA;
                       }
<St_Code>{CMD}"endcode" {
                         return RetVal_OK;
                       }
<St_Code>[^\\@\n]+     |
<St_Code>\n            |
<St_Code>.             {
  			 g_token->verb+=yytext;
  		       }
<St_HtmlOnly>{CMD}"endhtmlonly" {
                         return RetVal_OK;
                       }
<St_HtmlOnly>[^\\@\n$]+    |
<St_HtmlOnly>\n            |
<St_HtmlOnly>.             {
  			 g_token->verb+=yytext;
  		       }
<St_LatexOnly>{CMD}"endlatexonly" {
                         return RetVal_OK;
                       }
<St_LatexOnly>[^\\@\n]+     |
<St_LatexOnly>\n            |
<St_LatexOnly>.             {
  			 g_token->verb+=yytext;
  		       }
<St_Verbatim>{CMD}"endverbatim" {
                         return RetVal_OK;
                       }
<St_Verbatim>[^\\@\n]+     |
<St_Verbatim>\n            |
<St_Verbatim>.             { /* Verbatim text */
  			 g_token->verb+=yytext;
  		       }
<St_Title>"\""	       { // quoted title
  			 BEGIN(St_TitleQ);
  		       } 
<St_Title>[ \t]+       {
                         g_token->chars=yytext;
  			 return TK_WHITESPACE;
                       }
<St_Title>.	       { // non-quoted title
  			 unput(*yytext);
			 BEGIN(St_TitleN);
                       }
<St_Title>\n	       {
  			 return 0;
  		       }
<St_TitleN>"&"{ID}";"  { /* symbol */
                         g_token->name = yytext;
  		         return TK_SYMBOL;
                       }
<St_TitleN>{SPCMD1}    |   
<St_TitleN>{SPCMD2}    { /* special command */ 
                         g_token->name = yytext+1;
                         return TK_COMMAND;
                       }
<St_TitleN>{WORD1}     |
<St_TitleN>{WORD2}     { /* word */
                         g_token->name = yytext;
			 return TK_WORD;
                       }
<St_TitleN>[ \t]+      {
                         g_token->chars=yytext;
  			 return TK_WHITESPACE;
                       }
<St_TitleN>\n	       { /* new line => end of title */
                         unput(*yytext);
  			 return 0;
                       }
<St_TitleQ>"&"{ID}";"  { /* symbol */
                         g_token->name = yytext;
  		         return TK_SYMBOL;
                       }
<St_TitleQ>{SPCMD1}    |   
<St_TitleQ>{SPCMD2}    { /* special command */ 
                         g_token->name = yytext+1;
                         return TK_COMMAND;
                       }
<St_TitleQ>{WORD1NQ}   |
<St_TitleQ>{WORD2NQ}   { /* word */
                         g_token->name = yytext;
			 return TK_WORD;
                       }
<St_TitleQ>[ \t]+      {
                         g_token->chars=yytext;
  			 return TK_WHITESPACE;
                       }
<St_TitleQ>"\""	       { /* closing quote => end of title */
  			 BEGIN(St_TitleA);
  			 return 0;
                       }
<St_TitleQ>\n	       { /* new line => end of title */
                         unput(*yytext);
  			 return 0;
                       }
<St_TitleA>{BLANK}*{ID}{BLANK}*"="{BLANK}* { // title attribute
  			 g_token->name = yytext;
			 g_token->name = g_token->name.left(
			       g_token->name.find('=')).stripWhiteSpace();
  			 BEGIN(St_TitleV);
  		       }
<St_TitleV>[^ \t\r\n]+ { // attribute value
  			 g_token->chars = yytext;
			 BEGIN(St_TitleN);
			 return TK_WORD;
  		       }
<St_TitleV,St_TitleA>. {
  			 unput(*yytext);
  			 return 0;
                       }
<St_TitleV,St_TitleA>\n	 {
  			 return 0;
                       }

<St_Ref>{ID}	       {
  			 g_token->name=yytext;
			 return TK_WORD;
  		       }
<St_Ref>{BLANK}+       { 
  			 return 0;
                       }
<St_Ref>{BLANK}+"\""   {
  			 BEGIN(St_Ref2);
                       }
<St_Ref>\n	       {
                         unput(*yytext);
  			 return 0;
  		       }
<St_Ref>.	       {
                         unput(*yytext);
  			 return 0;
  		       }
<St_IntRef>[A-Z_a-z0-9.:#\-\+]+ {
                         g_token->name = yytext;
			 return TK_WORD;
  		       }
<St_IntRef>{BLANK}+"\"" {
                         BEGIN(St_Ref2);
                       }
<St_Ref2>"&"{ID}";"    { /* symbol */
                         g_token->name = yytext;
  		         return TK_SYMBOL;
                       }
<St_Ref2>{SPCMD1}      |   
<St_Ref2>{SPCMD2}      { /* special command */ 
                         g_token->name = yytext+1;
                         return TK_COMMAND;
                       }
<St_Ref2>{WORD1NQ}     |
<St_Ref2>{WORD2NQ}     {
                         /* word */
                         g_token->name = yytext;
			 return TK_WORD;
                       }
<St_Ref2>[ \t]+        {
                         g_token->chars=yytext;
  			 return TK_WHITESPACE;
                       }
<St_Ref2>"\""|\n       { /* " or \n => end of title */
  			 return 0;
                       }
<St_XRefItem>[0-9]+\n  {
  			 QCString numStr=yytext;
			 numStr=numStr.left(yyleng-1);
			 g_token->id=numStr.toInt();
			 return RetVal_OK;
  		       }
<St_Para,St_Title,St_Ref2>"<!--"     { /* html style comment block */
                         g_commentState = YY_START;
                         BEGIN(St_Comment); 
                       }
<St_Param>"\""[^\n\"]+"\"" {
  			 g_token->name = yytext+1;
			 g_token->name = g_token->name.left(yyleng-2);
			 return TK_WORD;
                       }
<St_Param>[^ \t\n,]+   {
  			 g_token->name = yytext;
			 return TK_WORD;
                       }
<St_Param>{WS}*","{WS}*  /* param separator */
<St_Param>{WS}	       {
                         g_token->chars=yytext;
                         return TK_WHITESPACE;
                       }
<St_File>{FILEMASK}    {
  			 g_token->name = yytext;
			 return TK_WORD;  
  		       }
<St_File>"\""[^\n\"]+"\"" {
  		         QCString text=yytext;
			 g_token->name = text.mid(1,text.length()-2);
			 return TK_WORD;
  		       }
<St_Pattern>[^\r\n]+   {
                         g_token->name = yytext;
                         g_token->name = g_token->name.stripWhiteSpace();
			 return TK_WORD;
  		       }
<St_Link>{LINKMASK}    {
                         g_token->name = yytext;
			 return TK_WORD;
                       }
<St_Comment>"-->"      { /* end of html comment */
                         BEGIN(g_commentState); 
                       }
<St_Comment>[^-\n]+       /* inside html comment */
<St_Comment>.             /* inside html comment */
<*>\n                  { 
                         warn(g_fileName,yylineno,"Error: Unexpected new line character"); 
		       }
<*>.                   { 
                         warn(g_fileName,yylineno,"Error: Unexpected character `%s'",yytext); 
		       }
%%

//--------------------------------------------------------------------------

void doctokenizerYYinit(const char *input,const char *fileName)
{
  g_inputString = input;
  g_inputPos = 0;
  g_fileName = fileName;
  BEGIN(St_Para);
}

void doctokenizerYYsetStatePara()
{
  BEGIN(St_Para);
}

void doctokenizerYYsetStateTitle()
{
  BEGIN(St_Title);
}

void doctokenizerYYsetStateCode()
{
  g_token->verb.resize(0);
  BEGIN(St_Code);
}

void doctokenizerYYsetStateHtmlOnly()
{
  g_token->verb.resize(0);
  BEGIN(St_HtmlOnly);
}

void doctokenizerYYsetStateLatexOnly()
{
  g_token->verb.resize(0);
  BEGIN(St_LatexOnly);
}

void doctokenizerYYsetStateVerbatim()
{
  g_token->verb.resize(0);
  BEGIN(St_Verbatim);
}

void doctokenizerYYsetStateParam()
{
  BEGIN(St_Param);
}

void doctokenizerYYsetStateXRefItem()
{
  BEGIN(St_XRefItem);
}

void doctokenizerYYsetStateFile()
{
  BEGIN(St_File);
}

void doctokenizerYYsetStatePattern()
{
  BEGIN(St_Pattern);
}

void doctokenizerYYsetStateLink()
{
  BEGIN(St_Link);
}

void doctokenizerYYsetStateRef()
{
  BEGIN(St_Ref);
}

void doctokenizerYYsetStateInternalRef()
{
  BEGIN(St_IntRef);
}

void doctokenizerYYcleanup()
{
  yy_delete_buffer( YY_CURRENT_BUFFER );
}

extern "C" { // some bogus code to keep the compiler happy
    void doctokenizerYYdummy() { yy_flex_realloc(0,0); }
}