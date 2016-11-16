Function ExtractString([String]$string, [String]$prefix, [String]$end_char) {
    $start_index = $string.IndexOf($prefix) + $prefix.Length
    $end_index = $string.IndexOf($end_char, $start_index)
    $string.Substring($start_index, $end_index - $start_index)
}

<# ============================ Authentication Setup =============================== #>
$user = '<user>'
$pass = '<password>'

$pair = "$($user):$($pass)"

$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))

$basicAuthValue = "Basic $encodedCreds"

$Headers = @{
    Authorization = $basicAuthValue
}

<# ============================ Get The Number And Type Of The Triggering Build =============================== #>
$res = Invoke-RestMethod -Uri http://172.18.51.40/httpAuth/app/rest/builds/%teamcity.build.id% -Method GET -Headers $Headers

$trigger_details = $res.build.triggered.details
$trigger_build_number_prefix = "triggeredByBuild='"
$trigger_build_number = ExtractString $trigger_details $trigger_build_number_prefix "'"

$trigger_build_type_prefix = "##triggeredByBuildType='"
$trigger_build_type = ExtractString $trigger_details $trigger_build_type_prefix "'"

<# ============================ Get Triggering Build Details =============================== #>
$url = "http://172.18.51.40/httpAuth/app/rest/builds/number:" + $trigger_build_number + ",buildType:" + $trigger_build_type
$res = Invoke-RestMethod -Uri $url -Method GET -Headers $Headers

$build_type_name = $res.build.buildType.name
$build_log_url = $res.build.webUrl
$build_agent_name = $res.build.agent.name

<# ============================ Get Testing Statistics Of The Triggering Build =============================== #>
$url = "http://172.18.51.40/httpAuth/app/rest/builds/number:" + $trigger_build_number + ",buildType:" + $trigger_build_type + "/statistics"
$res = Invoke-RestMethod -Uri $url -Method GET -Headers $Headers

$buildStatus = $res.properties.property | Where-Object -Property name -Eq -Value BuildTestStatus | Select-Object -Property value
$buildStatus = $buildStatus.value
$failedTestCount = $res.properties.property | Where-Object -Property name -Eq -Value FailedTestCount | Select-Object -Property value
$failedTestCount = $failedTestCount.value
$ignoredTestCount = $res.properties.property | Where-Object -Property name -Eq -Value IgnoredTestCount | Select-Object -Property value
$ignoredTestCount = $ignoredTestCount.value
$passedTestCount = $res.properties.property | Where-Object -Property name -Eq -Value PassedTestCount | Select-Object -Property value
$passedTestCount = $passedTestCount.value

<# ============================ Prepare Notification Message Of Slack =============================== #>
$failedTestCount = If ($failedTestCount.Length -Eq 0) {"0"} Else {$failedTestCount}
$testResult = If ($buildStatus -Eq "1") {"Tests Passed."} Else {"Tests Failed!!!"}
$color = If ($buildStatus -Eq "1") {"good"} Else {"danger"}

$postSlackMessage = @{
channel = "#ci_integration";
username = $build_agent_name;
icon_url = "http://build.tapadoo.com/img/icons/TeamCity32.png";
attachments = @(@{
color = $color;
fallback = "UAT Notification";
pretext = "<" + $build_log_url + "|#" + $trigger_build_number + "> of " + $build_type_name + " build is already finished.";
title = "<" + $build_log_url + "|#" + $trigger_build_number + ">";
author_name = $build_type_name;
fields = @(
@{title = "Result:"; value = $testResult;},
@{title = "Failed:"; value = "$failedTestCount"; short = "true";},
@{title = "Passed:"; value = "$passedTestCount"; short = "true";}
);
});
}

<# ============================ Post Notification Message To Slack =============================== #>
Invoke-RestMethod -Uri https://hooks.slack.com/services/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 -Method POST -Body (ConvertTo-Json $postSlackMessage -Depth 5)
