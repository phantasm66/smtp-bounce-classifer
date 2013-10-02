#!/usr/bin/ruby

require 'base64'
require 'time'
require 'date'

our_domain = 'mydomain.com'
classifier_log = '/var/log/smtp-bounce-classifer.log'
raw_bounce_log = '/var/log/smtp-bounce-classifier-RAW-BOUNCE.log'

input = ARGF.read
datetime = Time.now.to_s.split[0..1].join(' ')

dsn = input.encode("UTF-16BE", :invalid => :replace).encode("UTF-8")
dsn = dsn.gsub("=\n", '')

x_rcpt = dsn.match(/\nX-rcpt:\s*(.*)\n/)

if x_rcpt.nil?
  x_rcpt = dsn..match(/To:(.*)@#{Regexp.escape(our_domain)}\n/)
  x_rcpt = x_rcpt[1] unless x_rcpt.nil?
else
  x_rcpt = x_rcpt[1]
end

rcpt = x_rcpt.strip.downcase
domain = rcpt.split("@")[1]

# BEGIN: classifiers for feedback loops
if dsn.match(/Feedback-Type:/)
  classification = "fbl"
elsif dsn.match(/From:\sstaff@hotmail\.com/)
  classification = "fbl"
elsif dsn.match(/From:.*@arf\.mail\.yahoo/)
  classification = "fbl"
elsif dsn.match(/Subject:\s*unsubscribe/i)
  classification = "fbl"

# BEGIN: classifier for expired messages
elsif dsn.match(/Status:\s4\.\d\.\d/i)
  classification = "expired"

# BEGIN: classifiers for Diagnostic-Code header
elsif diagnostic_code = dsn.match(/Diagnostic-Code: (.*?)\n--/m)
  dsn_reason = diagnostic_code[1]
  dsn_reason = dsn_reason.to_s
  dsn_reason.gsub!(/\n/, '')
  dsn_reason.gsub!(/\s+/, ' ')

  case dsn_reason
    when /njabl/i
      classification = "njabl"
    when /message.*(size\sexceeds|too\slarge)/i
      classification = "msgsize"
    when /
      (temporar.*(problem|reject)|
      insufficient.*resources|
      out\sof\ssequence|
      mail.*loop.*detected|
      (service|transport)\sunavailable)
      /xi
      classification = "tmperr"
    when /
      (invalid|disabled|deactivated|malformed|norelay|inactiv(e|ity)|
      no.*(account|such|mailbox|address)|
      (address(ee?)|user).*(not\slisted|failed|doesn|unknown)|
      not\s(exist|found|.*valid|our\scustomer)|
      unknown(.*?)\s(user|alias|recipient)|
      alias.*valid|
      address\slookup.*fail|
      format.*address|
      unrouteable\saddress|
      (recipient|address).*\s(rejected|no\slonger)|
      none\s.*servers.*respond|
      no\s(route\sto\shost|valid|recipient)|
      hop\scount\sexceeded|
      RP:RDN.*xrnet|
      too\smany\shops|
      list\sof\sallowed\srcpthosts|
      user.*(reject|suspend)|
      doesn.*\shandle\smail\sfor|
      (user|recipient).*(not|only|unknown)|
      (access|relay).*\sdenied|
      MX\spoints\sto|
      refused\sdue\sto\srecipient|
      (account|mailbox|address|recipient).*
      (reserved|suspended|unavailable|not)|
      loops\sback\sto\smyself)
      /xi
      classification = "deadrcpt"
    when /
      (\s550\s5\.7\.1|
      too\s(many|fast|much)|slow\sdown|throttl(e|ing)|
      to\sabuse|excessive|bl(a|o)cklist|
      (junk|intrusion)|
      listed\sat|
      client.*not\sauthenticated|
      administrative.*prohibit|
      connection\srefused|
      connection.*(timed\sout|limit)|
      refused.*(mxrate|to\stalk)|
      can.*connect\sto\s.*psmtp|
      reject.*(content|policy)|
      not\saccept.*mail|
      message.*re(fused|ject)|
      transaction\sfailed.*psmtp|
      sorbs|rbl|spam|spamcop|block|den(y|ied)|
      unsolicited|
      not\sauthorized\sfrom\sthis\sip|
      reject\smail\sfrom|try\sagain\slater)
      /xi
      classification = "blocked"
    when /
      (overquota|over\squota|quota\sexceed|
      exceeded.*storage|
      (size|storage|mailbox).*(full|exceed)|
      full\s.*mailbox)
      /xi
      classification = "fullbox"
    when /message.*delayed/i
      classification = "delaydsn"
    else
      classification = "unclassified"
  end

# BEGIN: classifiers for no Diagnostic-Code header
elsif dsn.match(/X-Autoreply:\s*yes/i)
  classification = "autoreply"
elsif dsn.match(/Subject:.*(out\s+of.*office|auto.*re(ply|spon))/i)
  classification = "autoreply"
elsif dsn.match(/\s\(aol;\saway\)/i)
  classification = "autoreply"
elsif dsn.match(/auto-submitted:\s*auto-replied/i)
  classification = "autoreply"

# BEGIN: message delayed notification
elsif dsn.match(/(Action:\s*delayed|Will-Retry-Until)/i)
  classification = "delaydsn"
elsif dsn.match(/Subject:.*delayed\smail/i)
  classification = "delaydsn"
elsif dsn.match(/Subject:.*delivery.*status.*delay/i)
  classification = "delaydsn"
elsif dsn.match(/delivery\sto.*has\sbeen\sdelayed/i)
  classification = "delaydsn"

# BEGIN: dead recipient address
elsif dsn.match(/this\suser\sdoesn\'t\shave\sa\s.*\saccount/i)
  classification = "deadrcpt"
elsif dsn.match(/user.*doesn.*mail.*your.*address/i)
  classification = "deadrcpt"
elsif dsn.match(/in\smy\scontrol.*locals/i)
  classification = "deadrcpt"
elsif dsn.match(/invalid.*mailbox/i)
  classification = "deadrcpt"
elsif dsn.match(/user\sunknown/i)
  classification = "deadrcpt"
elsif dsn.match(/message.*not\sbe\sdelivered/i)
  classification = "deadrcpt"
elsif dsn.match(/address\swas\snot\sfound/i)
  classification = "deadrcpt"
elsif dsn.match(/protected.*bluebottle/i)
  classification = "deadrcpt"
elsif dsn.match(/hop\scount\sexceeded/i)
  classification = "deadrcpt"
elsif dsn.match(/delivery\sto.*(failed|aborted\safter)/i)
  classification = "deadrcpt"

# BEGIN: full mailbox
elsif dsn.match(/(size|(in|mail)box).*(full|size|exceed|many\smessages|much\sdata)/i)
  classification = "fullbox"
elsif dsn.match(/quota.*exceed/i)
  classification = "fullbox"

# BEGIN: rbl/policy block
elsif dsn.match(/5\.7\.1.*(reject|spam)/i)
  classification = "blocked"
elsif dsn.match(/protected.*reflexion/i)
  classification = "blocked"
elsif dsn.match(/said:\s.*(spam|rbl|blocked|blacklist|abuse)/i)
  classification = "blocked"

# BEGIN: temporary error
elsif dsn.match(/open\smailbox\sfor\s.*\stemporary\serror/i)
  classification = "tmperr"
elsif dsn.match(/subject.*mail\ssystem\serror/i)
  classification = "tmperr"

# BEGIN: unclassified catchall
else
  classification = "unclassified"
end

bounce_data = "#{datetime} #{rcpt} #{domain} #{classification}"
File.open(classifier_log, "a") {|line| line.puts bounce_data}

if classification =~ /^(fbl|deadrcpt)$/
  File.open(raw_bounce_log, "a+") {|msg| msg.puts dsn.to_s}
end

