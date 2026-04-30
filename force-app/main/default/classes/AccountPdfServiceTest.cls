public class AccountPdfServiceTest {

public static void generateAccountPdf(Id accountId) {

Account acc = [
SELECT Name, Industry, Phone, Website
FROM Account
WHERE Id = :accountId
LIMIT 1
];

String html =
'<html>' +
'<body style="margin:0; font-family:Arial, Helvetica, sans-serif; background-color:#F3F6F9;">' +

'<table width="100%" style="background-color:#0176D3; color:white; padding:24px;">' +
'<tr>' +
'<td>' +
'<h1 style="margin:0; font-size:30px; font-weight:bold; letter-spacing:1px;">SALESFORCE GEEK</h1>' +
'<p style="margin:6px 0 0 0; font-size:13px; opacity:0.95;">PDF generated using Apex • Blob.toPdf()</p>' +
'</td>' +
'</tr>' +
'</table>' +

'<table width="92%" align="center" style="background-color:white; margin-top:22px; border:1px solid #D8DDE6; border-radius:8px;">' +

'<tr style="background-color:#EEF4FF;">' +
'<td colspan="2" style="padding:14px; font-size:15px; font-weight:bold; color:#032D60;">' +
'Account Information' +
'</td>' +
'</tr>' +

'<tr>' +
'<td style="padding:12px; border-bottom:1px solid #E5E5E5; color:#032D60;"><b>Account Name</b></td>' +
'<td style="padding:12px; border-bottom:1px solid #E5E5E5;">' + acc.Name + '</td>' +
'</tr>' +

'<tr>' +
'<td style="padding:12px; border-bottom:1px solid #E5E5E5; color:#032D60;"><b>Industry</b></td>' +
'<td style="padding:12px; border-bottom:1px solid #E5E5E5;">' + acc.Industry + '</td>' +
'</tr>' +

'<tr>' +
'<td style="padding:12px; border-bottom:1px solid #E5E5E5; color:#032D60;"><b>Phone</b></td>' +
'<td style="padding:12px; border-bottom:1px solid #E5E5E5;">' + acc.Phone + '</td>' +
'</tr>' +

'<tr>' +
'<td style="padding:12px; color:#032D60;"><b>Website</b></td>' +
'<td style="padding:12px;">' + acc.Website + '</td>' +
'</tr>' +
'</table>' +

// FOOTER
'<table width="100%" style="margin-top:28px; background-color:#F3F6F9; padding:12px;">' +
'<tr>' +
'<td style="text-align:center; font-size:11px; color:#5C6F8C;">' +
'PDF created using Apex Blob.toPdf() — Spring ’26' +
'</td>' +
'</tr>' +
'</table>' +

'</body></html>';

Blob pdfBlob = Blob.toPdf(html);

ContentVersion cv = new ContentVersion();
cv.Title = acc.Name + ' - PDF';
cv.PathOnClient = acc.Name + '.pdf';
cv.VersionData = pdfBlob;
insert cv;

ContentDocumentLink cdl = new ContentDocumentLink();
cdl.ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

cdl.LinkedEntityId = acc.Id;
cdl.ShareType = 'V';
cdl.Visibility = 'AllUsers';
insert cdl;
}
}