﻿enum Ensure {
    Absent;
    Present;
}

enum SAMLBinding {
    POST;
    Redirect;
    Artifact;
}

enum SAMLProtocol {
    SAMLAssertionConsumer;
    SAMLArtifactResolution;
    SAMLLogout;
    SAMLSingleSignOn;
}

enum SamlResponseSignatureValue{
    AssertionOnly;
    MessageAndAssertion;
    MessageOnly;
}

#region DSC Resource: cADFSFarm
function InstallADFSFarm {
    <#
    .Synopsis
    Performs the configuration of the Active Directory Federation Services farm.

    .Parameter
    #>
    [CmdletBinding(DefaultParameterSetName = 'CertificateThumbprintServiceAccount')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateThumbprintServiceAccount')]
        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateSubjectServiceAccount')]
        [pscredential] $ServiceCredential,
        [Parameter(Mandatory = $true)]
        [pscredential] $InstallCredential,
        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateThumbprintGMSA')]
        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateSubjectGMSA')]
        [string] $GroupServiceAccountIdentifier,
        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateThumbprintServiceAccount')]
        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateThumbprintGMSA')]
        [string] $CertificateThumbprint,
        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateSubjectServiceAccount')]
        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateSubjectGMSA')]
        [string] $CertificateSubject,
        [Parameter(Mandatory = $true)]
        [string] $DisplayName,
        [Parameter(Mandatory = $true)]
        [string] $ServiceName,
        [hashtable] $AdminConfiguration
    )

    $CmdletName = $PSCmdlet.MyInvocation.MyCommand.Name;

    if ($PSBoundParameters.CertificateSubject) {
        if ($CertificateSubject.Substring(0, 3) -ne 'CN=') {
            $CertificateSubject = "CN=$CertificateSubject"
        }
        $Certificate = Find-Certificate -Subject $CertificateSubject
        $CertificateThumbprint = $Certificate.Thumbprint
    }

    Write-Verbose -Message ('Entering function {0}' -f $CmdletName);

    $adfsConfig = @{
        CertificateThumbprint           = $CertificateThumbprint
        Credential                      = $installCredential
        FederationServiceDisplayName    = $DisplayName
        FederationServiceName           = $ServiceName
        OverwriteConfiguration          = $true

    }

    if ($serviceCredential){
        $adfsConfig.Add('ServiceAccountCredential', $serviceCredential);
    }
    else{
        $adfsConfig.Add('GroupServiceAccountIdentifier', $GroupServiceAccountIdentifier);
    }

    Write-Verbose -Message ('Start install');
    Install-AdfsFarm @adfsConfig
    Write-Verbose -Message ('End install');

    if($AdminConfiguration){
        Write-Verbose -Message 'Configuring Active Directory Federation Services (ADFS) properties.';
        $AdfsPropertiesNew = $AdminConfiguration
        $AdfsPropertiesNew.Add('DisplayName', $DisplayName);
        
        Set-AdfsProperties @AdfsPropertiesNew;
        
        if($AdfsPropertiesNew.CertificateDuration -and $Primary){
            Write-Verbose -Message ('Changing certificate duration. Force certificate renewal');
            Update-AdfsCertificate -Urgent
        }
    }

    Write-Verbose -Message ('Leaving function {0}' -f $CmdletName);
}

[DscResource()]
class cADFSFarm {
    <#
    The Ensure property is used to determine if the Active Directory Federation Service (ADFS) should be installed (Present) or not installed (Absent).
    #>
    [DscProperty(Mandatory)]
    [Ensure] $Ensure;

    <#
    The DisplayName property is the name of the Active Directory Federation Service (ADFS) that users will see when they are directed to the authentication page.
    #>
    [DscProperty(Mandatory)]
    [string] $DisplayName;

    <#
    The ServiceName property is the name of the Active Directory Federation Services (ADFS) service. For example: adfs-service.contoso.com.
    #>
    [DscProperty(key)]
    [string] $ServiceName;

    <#
    The CertificateThumbprint property is the thumbprint of the certificate, located in the local computer's certificate store, that will be bound to the
    Active Directory Federation Service (ADFS) farm.
    #>
    [DscProperty()]
    [string] $CertificateThumbprint;

    <#
    The CertificateSubject property is the subject of the certificate, located in the local computer's certificate store, that will be bound to the
    Active Directory Federation Service (ADFS) farm. Used when the certificate thumbprint is not known when generating the MOF.
    #>
    [DscProperty()]
    [string] $CertificateSubject;

    <#
    The ServiceCredential property is a PSCredential that represents the username/password that the
    #>
    [DscProperty()]
    [pscredential] $ServiceCredential;

    <#
    The name of the group service account to be used by the ADFS service
    #>
    [DscProperty()]
    [string] $GroupServiceAccountIdentifier;

    <#
    The InstallCredential property is a PSCredential that represents the username/password of an Active Directory user account that is a member of
    the Domain Administrators security group. This account will be used to install Active Directory Federation Services (ADFS).
    #>
    [DscProperty(Mandatory)]
    [pscredential] $InstallCredential;
    
    <#
    A string containing the hashtable of ADFS AdminConfiguration
    #>
    [DscProperty()]
    [String] $AdminConfiguration;

    [cADFSFarm] Get() {

        Write-Verbose -Message 'Starting retrieving ADFS Farm configuration.';

        try {
            Get-AdfsProperties -ErrorAction Stop;
        }
        catch {
            Write-Verbose -Message ('Error occurred while retrieving ADFS properties: {0}' -f $global:Error[0].Exception.Message);
        }

        Write-Verbose -Message 'Finished retrieving ADFS Farm configuration.';
        return $this;
    }

    [System.Boolean] Test() {
        # Assume compliance by default
        $Compliant = $true;


        Write-Verbose -Message 'Testing for presence of Active Directory Federation Services (ADFS) farm.';

        try {
            $Properties = Get-AdfsProperties -ErrorAction Stop;
        }
        catch {
            $Compliant = $false;
            return $Compliant;
        }

        if ($this.Ensure -eq 'Present') {
            Write-Verbose -Message 'Checking for presence of ADFS Farm.';
            if ($this.ServiceName -ne $Properties.HostName) {
                Write-Verbose -Message 'ADFS Service Name doesn''t match the desired state.';
                $Compliant = $false;
            }
            else{
                $AdfsConfig = Convert-StringToHashtable $this.AdminConfiguration

                $AdfsConfig.GetEnumerator() | ForEach-Object{
                    if($_.Value -ne $Properties."$($_.Name)"){
                        $Compliant = $false;
                    }
                }
            }
        }

        if ($this.Ensure -eq 'Absent') {
            Write-Verbose -Message 'Checking for absence of ADFS Farm.';
            if ($Properties) {
                Write-Verbose -Message
                $Compliant = $false;
            }
        }

        if($Compliant){
            Write-Verbose -Message 'Compliance status: true'
        }
        else{
            Write-Verbose -Message 'Compliance status: false'
        }
        
        return $Compliant;
    }

    [void] Set() {

        ### If ADFS Farm shoud be present, then go ahead and install it.
        if ($this.Ensure -eq [Ensure]::Present) {
            try {
                $AdfsProperties = Get-AdfsProperties -ErrorAction stop;
            }
            catch {
                $AdfsProperties = $false
            }

            if (!$AdfsProperties) {
                Write-Verbose -Message 'Installing Active Directory Federation Services (ADFS) farm.';
                $AdfsFarm = @{
                    InstallCredential = $this.InstallCredential;
                    DisplayName = $this.DisplayName;
                    ServiceName = $this.ServiceName;
                };

                if ($this.CertificateThumbprint) {
                    $AdfsFarm.Add('CertificateThumbprint', $this.CertificateThumbprint);
                }
                elseif ($this.CertificateSubject) {
                    $AdfsFarm.Add('CertificateSubject', $this.CertificateSubject);
                }
                else {
                    Throw "No Certificate details provided, cannot configure ADFS Farm."
                }

                if ($this.AdminConfiguration) {
                    $AdfsConfig = Convert-StringToHashtable $this.AdminConfiguration
                    $AdfsFarm.Add('AdminConfiguration', $AdfsConfig);
                }

                if($this.ServiceCredential) {
                    $AdfsFarm.Add('ServiceCredential', $this.ServiceCredential);
                }
                elseif ($this.GroupServiceAccountIdentifier) {
                    $AdfsFarm.Add('GroupServiceAccountIdentifier', $this.GroupServiceAccountIdentifier);
                }
                else {
                    Throw "No service account nor GMSA details provided, cannot configure ADFS Farm."
                }
                
                InstallADFSFarm @AdfsFarm;
            }

            if ($AdfsProperties) {
                Write-Verbose -Message 'Configuring Active Directory Federation Services (ADFS) properties.';
                if($this.AdminConfiguration){
                    $AdfsPropertiesNew = Convert-StringToHashtable $this.AdminConfiguration
                    $AdfsPropertiesNew.Add('DisplayName', $this.DisplayName);
                }
                else{
                    $AdfsPropertiesNew = @{
                        DisplayName = $this.DisplayName;
                    }
                }
                
                Set-AdfsProperties @AdfsPropertiesNew;
            }
        }

        if ($this.Ensure -eq [Ensure]::Absent) {
            ### From the help for Remove-AdfsFarmNode: The Remove-AdfsFarmNode cmdlet is deprecated. Instead, use the Uninstall-WindowsFeature cmdlet.
            Uninstall-WindowsFeature -Name ADFS-Federation;
        }

        return;
    }
}
#endregion


Function Get-CertificatesObjects {
    <#
    .Synopsis
    Get a list of X509Certificate2 object from an array containing their thumbprint. It only gets certificates in the computer personal store.

    .PARAMETER RequestSigningCertificate
    An array of string containing the thumbprint of the certificate to find.
    #>
    param(
        [Parameter(Mandatory = $true)][String[]]$RequestSigningCertificate
    )

    $certificates = @()
    $RequestSigningCertificate | ForEach-Object{
        $thumbprint = $_
        $certificates += Get-ChildItem -path cert:\LocalMachine\My | Where-Object{$_.thumbprint -eq $thumbprint}
    }

    return $certificates
}
    
#region DSC Resource: cADFSRelyingPartyTrust
[DscResource()]
class cADFSRelyingPartyTrust {
    ### Determines whether or not the ADFS Relying Party Trust should exist.
    [DscProperty()]
    [Ensure] $Ensure;

    ### The Name property must be unique to each ADFS Relying Party application in a farm.
    [DscProperty(Key)]
    [string] $Name;

    ### The identifiers are used to uniquely identify ADFS Relying Party applications.
    [DscProperty(Mandatory)]
    [string[]] $Identifier;

    ### The Notes property allows you to specify helpful notes to other administrators
    ### to help determine the purpose and configuration behind the Relying Party Trust.
    [DscProperty()]
    [string] $Notes;

    ### Transform rules are optional rules that perform mappings between identity attributes and claims.
    [DscProperty()]
    [string] $IssuanceTransformRules;

    ### Issuance authorization rules allow restriction of access based on user claims.
    ### More information: https://technet.microsoft.com/en-us/library/ee913560.aspx
    [DscProperty()]
    [string] $IssuanceAuthorizationRules = '';

    ### The WS-Federation Endpoint is an optional parameter that specifies the WS-Federation Passive URL for the relying party.
    [DscProperty()]
    [string] $WsFederationEndpoint;

    ### Enabling Relying Party monitoring enables automatic updating of Relying Party metadata from the Federation Metadata URL.
    ### More information: http://blogs.msdn.com/b/card/archive/2010/06/25/using-federation-metadata-to-establish-a-relying-party-trust-in-ad-fs-2-0.aspx
    [DscProperty()]
    [bool] $MonitoringEnabled = $false;

    [DscProperty()]
    [string[]] $ClaimsProviderName;

    ### Specifies which protocol profiles the relying party supports. The acceptable values for this parameter are: SAML, WsFederation, and WsFed-SAML.
    [DscProperty()]
    [string] $ProtocolProfile;

    ### Specifies the name of an access control policy
    [DscProperty()]
    [string] $AccessControlPolicyName;

    ### ndicates whether the Federation Service requires signed SAML protocol requests from the relying party. If you specify a value of $True, the Federation Service rejects unsigned SAML protocol requests.
    [DscProperty()]
    [bool] $SignedSamlRequestsRequired

    ### Specifies the thumbprint of the signing certificate
    [DscProperty()]
    [string[]] $SigningCertificateThumbprint;

    ### Specifies the response signatures that the relying party expects.
    [DscProperty()]
    [SamlResponseSignatureValue] $SamlResponseSignature

    ### Specifies the signature algorithm that the relying party uses for signing and verification.
    [DscProperty()]
    [ValidateSet("http://www.w3.org/2000/09/xmldsig#rsa-sha1","http://www.w3.org/2001/04/xmldsig-more#rsa-sha256")] 
    [String] $SignatureAlgorithm

    ### Specifies the skew, as in integer, for the time stamp that marks the beginning of the validity period
    [DscProperty()]
    [Int] $NotBeforeSkew

    ### Indicates whether the JSON Web Token (JWT) format should be used to issue a token on a WS-Federation request. By default, SAML tokens are issued over WS-Federation.
    [DscProperty()]
    [bool] $EnableJWT

    ### Specifies the duration, in minutes, for which the claims that are issued to the relying party are valid.
    [DscProperty()]
    [Int] $TokenLifetime

    [cADFSRelyingPartyTrust] Get() {
        $this.CheckDependencies();

        Write-Verbose -Message ('Retrieving the current Relying Party Trust configuration for {0}' -f $this.Name);

        $RelyingPartyTrust = $null;
        try {
            $RelyingPartyTrust = Get-AdfsRelyingPartyTrust -Name $this.Name -ErrorAction Stop;
        }
        catch {
        }

        $this.Name = $RelyingPartyTrust.Name;
        $this.IssuanceTransformRules = $RelyingPartyTrust.IssuanceTransformRules;
        $this.IssuanceAuthorizationRules = $RelyingPartyTrust.IssuanceAuthorizationRules;
        $this.ClaimsProviderName = $RelyingPartyTrust.ClaimsProviderName;
        $this.ProtocolProfile = $RelyingPartyTrust.ProtocolProfile;
        $this.MonitoringEnabled = $RelyingPartyTrust.MonitoringEnabled;
        $this.WsFederationEndpoint = $RelyingPartyTrust.WsFedEndpoint;
        $this.Notes = $RelyingPartyTrust.Notes;
        $this.Identifier = $RelyingPartyTrust.Identifier;
        $this.AccessControlPolicyName = $RelyingPartyTrust.AccessControlPolicyName;
        $this.SignedSamlRequestsRequired = $RelyingPartyTrust.SignedSamlRequestsRequired;
        $this.SignatureAlgorithm = $RelyingPartyTrust.SignatureAlgorithm;
        $this.SamlResponseSignature = $RelyingPartyTrust.SamlResponseSignature;
        $this.SigningCertificateThumbprint = $RelyingPartyTrust.RequestSigningCertificate | Foreach-object {$_.Thumbprint};
        $this.NotBeforeSkew = $RelyingPartyTrust.NotBeforeSkew;
        $this.EnableJWT = $RelyingPartyTrust.EnableJWT;
        $this.TokenLifetime = $RelyingPartyTrust.TokenLifetime

        return $this;
    }

    [bool] Test() {
        $this.CheckDependencies();

        ### Assume complaince unless a setting does not match.
        $Compliant = $true;

        $RelyingPartyTrust = $null;
        try {
            ### Retrieve the Relying Party Trust using the ADFS PowerShell commands.
            $RelyingPartyTrust = Get-AdfsRelyingPartyTrust -Name $this.Name -ErrorAction Stop;
            Write-Verbose -Message ('Successfully retrieved Relying Party Trust from ADFS named {0}' -f $this.Name);
        }
        catch {
            Write-Verbose -Message ('Error occurred attempting to retrieve Relying Party Trust with name {0}.' -f $this.Name);
            throw $PSItem;
            return $false;
        }

        #region Setting should be absent
        ### If the setting should be absent, but the Relying Party Trust exists, then the system is non-compliant.
        if ($this.Ensure -eq 'Absent') {
            if ($RelyingPartyTrust) {
                Write-Verbose -Message ('Relying Party Trust exists with name {0}. System is non-compliant.' -f $this.Name);
                $Compliant = $false;
            }
            else {
                Write-Verbose -Message ('Relying Party Trust does not exist with name {0}. System is compliant.' -f $this.Name);
                $Compliant = $true;
            }
            return $Compliant;
        }
        #endregion

        #region Setting should be present
        ### If $this.Ensure -eq 'Present' then the following code will execute
        if (!$RelyingPartyTrust) {
            Write-Verbose -Message ('Relying Party does not exist with name {0}.' -f $this.Name);
            return $false;
        }
        if ($RelyingPartyTrust.IssuanceAuthorizationRules -ne $this.IssuanceAuthorizationRules) {
            Write-Verbose -Message ('The current IssuanceAuthorizationRules property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.IssuanceAuthorizationRules, $this.IssuanceAuthorizationRules);
            $Compliant = $false;
        }
        if (($RelyingPartyTrust.IssuanceTransformRules -replace '\s', '') -ne ($this.IssuanceTransformRules -replace '\s', '')) {
            Write-Verbose -Message ('The current IssuanceTransformRules property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.IssuanceTransformRules.Trim(), $this.IssuanceTransformRules.Trim());
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.ClaimsProviderName -ne $this.ClaimsProviderName) {
            Write-Verbose -Message ('The current ClaimsProviderName property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.ClaimsProviderName, $this.ClaimsProviderName);
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.ProtocolProfile -ne $this.ProtocolProfile) {
            Write-Verbose -Message ('The current ProtocolProfile property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.ProtocolProfile, $this.ProtocolProfile);
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.MonitoringEnabled -ne $this.MonitoringEnabled) {
            Write-Verbose -Message ('The current MonitoringEnabled property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.MonitoringEnabled, $this.MonitoringEnabled);
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.Identifier -ne $this.Identifier) {
            Write-Verbose -Message ('The current Identifier property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.Identifier, $this.Identifier);
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.WsFedEndpoint -ne ([System.Uri]$this.WsFederationEndpoint)) {
            Write-Verbose -Message ('The current WsFederationEndpoint property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.WsFedEndpoint, $this.WsFederationEndpoint);
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.Notes -ne $this.Notes) {
            Write-Verbose -Message ('The current Notes property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.Notes, $this.Notes);
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.AccessControlPolicyName -ne $this.AccessControlPolicyName) {
            Write-Verbose -Message ('The current AccessControlPolicyName property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.AccessControlPolicyName, $this.AccessControlPolicyName);
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.SignedSamlRequestsRequired -ne $this.SignedSamlRequestsRequired) {
            Write-Verbose -Message ('The current SignedSamlRequestsRequired property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.SignedSamlRequestsRequired, $this.SignedSamlRequestsRequired);
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.SamlResponseSignature -ne $this.SamlResponseSignature) {
            Write-Verbose -Message ('The current SamlResponseSignature property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.SamlResponseSignature, $this.SamlResponseSignature);
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.SignatureAlgorithm -ne $this.SignatureAlgorithm) {
            Write-Verbose -Message ('The current SignatureAlgorithm property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.SignatureAlgorithm, $this.SignatureAlgorithm);
            $Compliant = $false;
        }
        
        $certificates = Get-CertificatesObjects -ThumbprintArray $this.RequestSigningCertificate
        if ($RelyingPartyTrust.RequestSigningCertificate -ne $certificates) {
            Write-Verbose -Message ('The current RequestSigningCertificate property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.RequestSigningCertificate, $certificates);
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.NotBeforeSkew -ne $this.NotBeforeSkew) {
            Write-Verbose -Message ('The current NotBeforeSkew property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.NotBeforeSkew, $this.NotBeforeSkew);
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.EnableJWT -ne $this.EnableJWT) {
            Write-Verbose -Message ('The current EnableJWT property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.EnableJWT, $this.EnableJWT);
            $Compliant = $false;
        }
        if ($RelyingPartyTrust.TokenLifetime -ne $this.TokenLifetime) {
            Write-Verbose -Message ('The current TokenLifetime property value ({0}) does not match the desired configuration ({1}).' -f $RelyingPartyTrust.TokenLifetime, $this.TokenLifetime);
            $Compliant = $false;
        }

        

        if ($Compliant) {
            Write-Verbose -Message ('ADFS Relying Party ({0}) is compliant' -f $this.Name);
        }
        return $Compliant;
        #endregion
    }

    [void] Set() {
        $this.CheckDependencies();

        ### Build a HashTable of what the configuration settings should look like.
        $certificates = Get-CertificatesObjects -ThumbprintArray $this.RequestSigningCertificate
        $RelyingPartyTrust = @{
            Identifier = $this.Identifier;
            IssuanceTransformRules = $this.IssuanceTransformRules;
            ProtocolProfile = $this.ProtocolProfile;
            MonitoringEnabled = $this.MonitoringEnabled;
            WsFedEndpoint = [System.Uri]$this.WsFederationEndpoint;
            Notes = $this.Notes;
            Name = $this.Name;
        };

        ### Add the ClaimsProviderName, only if it was specified by the user.
        if ($this.ClaimsProviderName) {
            $RelyingPartyTrust.Add('ClaimsProviderName', $this.ClaimsProviderName);
        }

        if ($this.SignedSamlRequestsRequired) {
            $RelyingPartyTrust.Add('SignedSamlRequestsRequired', $this.SignedSamlRequestsRequired);
        }

        if ($this.SignatureAlgorithm) {
            $RelyingPartyTrust.Add('SignatureAlgorithm', $this.SignatureAlgorithm);
        }

        if ($this.SamlResponseSignature) {
            $RelyingPartyTrust.Add('SamlResponseSignature', $this.SamlResponseSignature);
        }

        if ($certificates) {
            $RelyingPartyTrust.Add('RequestSigningCertificate', $certificates);
        }

        if ($this.NotBeforeSkew) {
            $RelyingPartyTrust.Add('NotBeforeSkew', $this.NotBeforeSkew);
        }

        if ($this.EnableJWT) {
            $RelyingPartyTrust.Add('EnableJWT', $this.EnableJWT);
        }

        if ($this.TokenLifetime) {
            $RelyingPartyTrust.Add('TokenLifetime', $this.TokenLifetime);
        }

        if ($this.IssuanceAuthorizationRules) {
            $RelyingPartyTrust.Add('IssuanceAuthorizationRules', $this.IssuanceAuthorizationRules);
        }

        if ($this.AccessControlPolicyName) {
            $RelyingPartyTrust.Add('AccessControlPolicyName', $this.AccessControlPolicyName);
        }

        ### Retrieve the existing Relying Party Configuration
        $CurrentRelyingPartyTrust = $null;
        try {
            $CurrentRelyingPartyTrust = Get-AdfsRelyingPartyTrust -Name $this.Name -ErrorAction Stop;
        }
        catch {
            Write-Verbose -Message 'Error occurred while retrieving Relying Party Trust!';
            throw $PSItem;
            return;
        }

        #region DSC Resource Absent
        if ($this.Ensure -eq 'Absent') {
            if ($CurrentRelyingPartyTrust) {
                Write-Verbose -Message 'Relying Party Trust should be absent, but it exists. Removing it.';
                Remove-AdfsRelyingPartyTrust -TargetRelyingParty $CurrentRelyingPartyTrust -ErrorAction Stop;
            }
            else {
                Write-Verbose -Message 'Relying Party Trust does not exist, so we are already compliant. You should never see this message.';
            }
            return;
        }
        #endregion

        #region DSC Resource Present
        $this.DisplayHashTable($RelyingPartyTrust);
        if (!$CurrentRelyingPartyTrust) {
            ### This code executes if the Relying Party Trust does not exist.
            Write-Verbose -Message ('The ADFS Relying Party Trust ({0}) does not exist. Creating it.' -f $this.Name);
            Add-AdfsRelyingPartyTrust @RelyingPartyTrust;
        }
        else {
            Write-Verbose -Message ('The ADFS Relying Party Trust ({0}) already exists, but its configuration does not match desired state. Updating configuration.' -f $this.Name);
            Set-AdfsRelyingPartyTrust @RelyingPartyTrust -TargetName $RelyingPartyTrust.Name;
        }
        #endregion

        Write-Verbose -Message 'Completed the Set() method in the cADFSRelyingPartyTrust DSC Resource.';
        return;
    }

    ### Helper method to validate that dependencies are met for this DSC Resource.
    [bool] CheckDependencies() {
        Write-Verbose -Message 'Checking ADFS dependencies was invoked.';
        try {
            Get-WindowsFeature -Name ADFS -ErrorAction Stop;
            Get-AdfsProperties -ErrorAction Stop;
        }
        catch {
            Write-Verbose -Message 'Error occurred during ADFS dependency checking!';
            throw $PSItem;
            return $false;
        }

        Write-Verbose -Message 'ADFS dependency checking completed.';
        return $true;
    }

    [void] DisplayHashTable([HashTable] $Input) {
        foreach ($Key in $Input.Keys) {
            Write-Verbose -Message ('{0} :: {1}' -f $Key, $Input[$Key]);
        }
        return;
    }
}
#endregion

#region DSC Resource: cADFSSamlEndpoint
[DscResource()]
class cADFSSamlEndpoint {
    ### Determines whether or not the ADFS SAML Endpoint should exist.
    [DscProperty()]
    [Ensure] $Ensure;

    ### The Name property must be unique to each ADFS Relying Party application in a farm.
    [DscProperty(Key)]
    [string] $Name;

    ### Binding type (POST, Redirect, Artifact)
    [DscProperty(Mandatory)]
    [SAMLBinding] $Binding;

    ### Index of the Endpoint
    [DscProperty(Key)]
    [Int] $Index;

    ### Set this Endpoint as the default endpoint
    [DscProperty()]
    [Bool] $IsDefault;

    ### Uri of the Endpoint
    [DscProperty(Mandatory)]
    [String] $Location;

    ### SAML Protocol that this endpoint implements
    [DscProperty(Key)]
    [SAMLProtocol] $Protocol;

    ### Retrieves the current state of the SAML Endpoint of a ADFS Relying Party Trust
    [cADFSSamlEndpoint] Get() {
        Write-Verbose -Message 'Starting retrieving list of all current SAML Endpoints for the ADFS Relying Party Trust';
        $AllCurrentSAMLEndpoints = (Get-AdfsRelyingPartyTrust -Name $this.Name).SamlEndpoints;
        Write-Verbose -Message 'Finished retrieving list of all current SAML Endpoints for the ADFS Relying Party Trust';

        Write-Verbose -Message 'Starting retrieving SAML Endpoint at Index $this.Index';
        $CurrentSAMLEndpoint = $AllCurrentSAMLEndpoints | Where-Object { $_.Index -eq $this.Index };
        Write-Verbose -Message 'Finished retrieving SAML Endpoint at Index $this.Index';

        $this.Binding = $CurrentSAMLEndpoint.Binding;
        $this.Index = $CurrentSAMLEndpoint.Index;
        $this.IsDefault = $CurrentSAMLEndpoint.IsDefault;
        $this.Location = $CurrentSAMLEndpoint.Location;
        $this.Protocol = $CurrentSAMLEndpoint.Protocol;

        return $this;

    }

    ### Test the validity of the current SAML Endpoint against the desired configuration
    [bool] Test() {
        Write-Verbose -Message 'Starting evaluating SAML Endpoint against desired state.';

        $AllCurrentSAMLEndpoints = (Get-AdfsRelyingPartyTrust -Name $this.Name).SamlEndpoints;
        $CurrentSAMLEndpoint = $AllCurrentSAMLEndpoints | Where-Object { $_.Index -eq $this.Index };

        ### Assume that the system is complian, unless one of the specific settings does not match.
        $Compliance = $true;

        if ($this.Binding -ne $CurrentSAMLEndpoint.Binding) {
            Write-Verbose -Message 'Binding setting does not match desired configuration.';
            $Compliance = $false;
        }
        if ($this.IsDefault -ne $CurrentSAMLEndpoint.IsDefault) {
            Write-Verbose -Message 'IsDefault setting does not match desired configuration.';
            $Compliance = $false;
        }
        if ($this.Location -ne $CurrentSAMLEndpoint.Location) {
            Write-Verbose -Message 'Location Uri setting does not match desired configuration.';
            $Compliance = $false;
        }
        if ($this.Protocol -ne $CurrentSAMLEndpoint.Protocol) {
            Write-Verbose -Message 'Protocol setting does not match desired configuration.';
            $Compliance = $false;
        }

        if ($Compliance) {
            Write-Verbose -Message 'All SAML Endpoint settings match desired configuration.';
        }
        return $Compliance;
    }

    [void] Set() {
        Write-Verbose -Message 'Starting setting SAML Endpoint configuration.';
        $SAMLEndpoint = @{
            Binding = $this.Binding;
            Uri = $this.Location;
            Protocol = $this.Protocol;
        }
        if ($this.IsDefault) {
            $SAMLEndpoint.Add('IsDefault', $this.IsDefault);
        }

        $ReplacementSAMLEndpoint = New-AdfsSamlEndpoint @SAMLEndpoint;

        $AllNewSAMLEndpoints = @();
        $AllCurrentSAMLEndpoints = (Get-AdfsRelyingPartyTrust -Name $this.Name).SamlEndpoints;
        ForEach ($CurrentSAMLEndpoint in $AllCurrentSAMLEndpoints) {
            If ($CurrentSAMLEndpoint.Index -eq $this.Index) {
                $AllNewSAMLEndpoints += $ReplacementSAMLEndpoint;
            } Else {
                $AllNewSAMLEndpoints += $CurrentSAMLEndpoint;
            }
        }

        Set-AdfsRelyingPartyTrust -TargetName $this.Name -SamlEndpoint $AllNewSAMLEndpoints;
        Write-Verbose -Message 'Finished setting ADFS Global Authentication configuration.';
    }
}
#endregion

#region DSC Resource: cADFSGlobalAuthenticationPolicy
[DscResource()]
class cADFSGlobalAuthenticationPolicy {
    [DscProperty(Key)]
    [string] $Name = 'Policy';

    [DscProperty()]
    [bool] $DeviceAuthenticationEnabled = $false;

    [DscProperty()]
    [string[]] $PrimaryExtranetAuthenticationProvider = @('FormsAuthentication');

    [DscProperty()]
    [string[]] $PrimaryIntranetAuthenticationProvider = @('WindowsAuthentication');

    [DscProperty()]
    [string[]] $AdditionalAuthenticationProvider = @();

    [DscProperty()]
    [bool] $WindowsIntegratedFallbackEnabled = $true;

    ### Retrieves the current state of the ADFS Global Authentication Policy.
    [cADFSGlobalAuthenticationPolicy] Get() {
        Write-Verbose -Message 'Starting retrieving configuration for ADFS Global Authentication Policy.';
        $CurrentPolicy = Get-AdfsGlobalAuthenticationPolicy;

        $this.PrimaryExtranetAuthenticationProvider = $CurrentPolicy.PrimaryExtranetAuthenticationProvider;
        $this.PrimaryIntranetAuthenticationProvider = $CurrentPolicy.PrimaryIntranetAuthenticationProvider;
        $this.AdditionalAuthenticationProvider = $CurrentPolicy.AdditionalAuthenticationProvider;
        $this.DeviceAuthenticationEnabled = $CurrentPolicy.DeviceAuthenticationEnabled;

        Write-Verbose -Message 'Finished retrieving configuration for ADFS Global Authentication Policy.';
        return $this;
    }

    ### Tests the validity of the current policy against the
    [bool] Test() {
        Write-Verbose -Message 'Starting evaluating ADFS Global Authentication Policy against desired state.';

        $CurrentPolicy = Get-AdfsGlobalAuthenticationPolicy;

        ### Assume that the system is complaint, unless one of the specific settings does not match.
        $Compliance = $true;

        ### NOTE: Array comparisons must be done using Compare-Object
        if (Compare-Object -ReferenceObject $this.PrimaryExtranetAuthenticationProvider -DifferenceObject $CurrentPolicy.PrimaryExtranetAuthenticationProvider) {
            Write-Verbose -Message 'Primary Extranet Authentication Provider does not match desired configuration.';
            $Compliance = $false;
        }
        if (Compare-Object -ReferenceObject $this.PrimaryIntranetAuthenticationProvider -DifferenceObject $CurrentPolicy.PrimaryIntranetAuthenticationProvider) {
            Write-Verbose -Message 'Primary Intranet Authentication Provider does not match desired configuration.';
            $Compliance = $false;
        }
        if (Compare-Object -ReferenceObject $this.AdditionalAuthenticationProvider -DifferenceObject $CurrentPolicy.AdditionalAuthenticationProvider) {
            Write-Verbose -Message 'Additional Authentication Provider does not match desired configuration.';
            $Compliance = $false;
        }
        if ($this.DeviceAuthenticationEnabled -ne $CurrentPolicy.DeviceAuthenticationEnabled) {
            Write-Verbose -Message 'Device Authentication setting does not match desired configuration.';
            $Compliance = $false;
        }
        if ($this.WindowsIntegratedFallbackEnabled -ne $CurrentPolicy.WindowsIntegratedFallbackEnabled) {
            Write-Verbose -Message 'Windows Integrated Fallback setting does not match desired configuration.';
            $Compliance = $false;
        }

        if ($Compliance) {
            Write-Verbose -Message 'All ADFS Global Authentication settings match desired configuration.';
        }
        return $Compliance;
    }

    [void] Set() {
        Write-Verbose -Message 'Starting setting ADFS Global Authentication configuration.';
        $GlobalAuthenticationPolicy = @{
            PrimaryExtranetAuthenticationProvider = $this.PrimaryExtranetAuthenticationProvider;
            PrimaryIntranetAuthenticationProvider = $this.PrimaryIntranetAuthenticationProvider;
            AdditionalAuthenticationProvider = $this.AdditionalAuthenticationProvider;
            DeviceAuthenticationEnabled = $this.DeviceAuthenticationEnabled;
            WindowsIntegratedFallbackEnabled = $this.WindowsIntegratedFallbackEnabled;
        };
        Set-AdfsGlobalAuthenticationPolicy @GlobalAuthenticationPolicy;
        Write-Verbose -Message 'Finished setting ADFS Global Authentication configuration.';
    }
}
#endregion

function AddADFSNode {
    <#
    .Synopsis
    Performs the configuration of the Active Directory Federation Services farm.

    .Parameter
    #>
    [CmdletBinding(DefaultParameterSetName = 'CertificateThumbprint')]
    param (
        [Parameter(Mandatory = $true)]
        [pscredential] $ServiceCredential,
        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateThumbprint')]
        [string] $CertificateThumbprint,
        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateSubject')]
        [string] $CertificateSubject,
        [Parameter(Mandatory = $true)]
        [string] $PrimaryADFSServer
    )

    $CmdletName = $PSCmdlet.MyInvocation.MyCommand.Name;

    if ($PSBoundParameters.CertificateSubject) {
        if ($CertificateSubject.Substring(0, 3) -ne 'CN=') {
            $CertificateSubject = "CN=$CertificateSubject"
        }
        $Certificate = Find-Certificate -Subject $CertificateSubject
        $CertificateThumbprint = $Certificate.Thumbprint
    }

    Write-Verbose -Message ('Entering function {0}' -f $CmdletName);

    Add-AdfsFarmNode -CertificateThumbprint:$CertificateThumbprint `
    -ServiceAccountCredential $serviceCredential `
    -PrimaryComputerName $PrimaryADFSServer

    Write-Verbose -Message ('Leaving function {0}' -f $CmdletName);
}

[DscResource()]
class cADFSNode {
    <#
    The Ensure property is used to determine if the Active Directory Federation Service (ADFS) should be installed (Present) or not installed (Absent).
    #>
    [DscProperty(Mandatory)]
    [Ensure] $Ensure;

    <#
    The PrimaryADFSServer property is the name of the Active Directory Federation Services (ADFS) Primary Server.
    #>
    [DscProperty(key)]
    [string] $PrimaryADFSServer;

    <#
    The CertificateThumbprint property is the thumbprint of the certificate, located in the local computer's certificate store, that will be bound to the
    Active Directory Federation Service (ADFS) farm.
    #>
    [DscProperty()]
    [string] $CertificateThumbprint;

    <#
    The CertificateSubject property is the subject of the certificate, located in the local computer's certificate store, that will be bound to the
    Active Directory Federation Service (ADFS) farm. Used when the certificate thumbprint is not known when generating the MOF.
    #>
    [DscProperty()]
    [string] $CertificateSubject;

    <#
    The ServiceCredential property is a PSCredential that represents the username/password that the
    #>
    [DscProperty(Mandatory)]
    [pscredential] $ServiceCredential;

    [cADFSNode] Get() {

        Write-Verbose -Message 'Starting retrieving ADFS Farm configuration.';

        try {
            $AdfsProperties = Get-AdfsProperties -ErrorAction Stop;
        }
        catch {
            Write-Verbose -Message ('Error occurred while retrieving ADFS properties: {0}' -f $global:Error[0].Exception.Message);
        }

        Write-Verbose -Message 'Finished retrieving ADFS Farm configuration.';
        return $this;
    }

    [System.Boolean] Test() {
        # Assume compliance by default
        $Compliant = $true;


        Write-Verbose -Message 'Testing for presence of Active Directory Federation Services (ADFS) farm.';

        try {
            $Properties = Get-AdfsProperties -ErrorAction Stop;
        }
        catch {
            $Compliant = $false;
            return $Compliant;
        }

        if ($this.Ensure -eq 'Present') {
            Write-Verbose -Message 'Checking for presence of ADFS Farm.';
            # Check that this a node, not the server....
            # if ($env:COMPUTERNAME -ne $Properties.HostName) {
            #     Write-Verbose -Message 'ADFS Service Name doesn''t match the desired state.';
            #     $Compliant = $false;
            # }
        }

        if ($this.Ensure -eq 'Absent') {
            Write-Verbose -Message 'Checking for absence of ADFS Farm.';
            if ($Properties) {
                Write-Verbose -Message
                $Compliant = $false;
            }
        }

        return $Compliant;
    }

    [void] Set() {

        ### If ADFS Farm shoud be present, then go ahead and install it.
        if ($this.Ensure -eq [Ensure]::Present) {
            try {
                $AdfsProperties = Get-AdfsProperties -ErrorAction stop;
            }
            catch {
                $AdfsProperties = $false
            }

            if (!$AdfsProperties) {
                Write-Verbose -Message 'Installing Active Directory Federation Services (ADFS) farm.';

                $AdfsNode = @{
                    ServiceCredential = $this.ServiceCredential;
                    PrimaryADFSServer = $this.PrimaryADFSServer;
                };

                if ($this.CertificateThumbprint) {
                    $AdfsNode.Add('CertificateThumbprint', $this.CertificateThumbprint);
                }
                elseif ($this.CertificateSubject) {
                    $AdfsNode.Add('CertificateSubject', $this.CertificateSubject);
                }
                else {
                    Throw "No Certificate details provided, cannot configure ADFS Farm."
                }

                AddADFSNode @AdfsNode;
            }

            if ($AdfsProperties) {
                Write-Verbose -Message 'Configuring Active Directory Federation Services (ADFS) properties.';
                $AdfsProperties = @{
                    DisplayName = $this.DisplayName;
                };
                Set-AdfsProperties @AdfsProperties;
            }
        }

        if ($this.Ensure -eq [Ensure]::Absent) {
            ### From the help for Remove-AdfsFarmNode: The Remove-AdfsFarmNode cmdlet is deprecated. Instead, use the Uninstall-WindowsFeature cmdlet.
            Uninstall-WindowsFeature -Name ADFS-Federation;
        }

        return;
    }
}


[DscResource()]
class cADFSDeviceRegistration {
    <#
    The Ensure property is used to determine if the Active Directory Federation Service (ADFS) should be installed (Present) or not installed (Absent).
    #>
    [DscProperty(Mandatory)]
    [Ensure] $Ensure;

    [DscProperty(key)]
    [string] $DomainName;

    [DscProperty(Mandatory)]
    [string] $ServiceAccountName
    
    <#
    The ServiceCredential property is a PSCredential that represents the username/password that the
    #>
    [DscProperty(Mandatory)]
    [pscredential] $ServiceCredential;

    <#
    The InstallCredential property is a PSCredential that represents the username/password of an Active Directory user account that is a member of
    the Domain Administrators security group. This account will be used to install Active Directory Federation Services (ADFS).
    #>
    [DscProperty(Mandatory)]
    [pscredential] $InstallCredential;

    [DscProperty()]
    [Int] $RegistrationQuota;

    [DscProperty()]
    [Int] $MaximumRegistrationInactivityPeriod;
    
    [cADFSDeviceRegistration] Get() {

        Write-Verbose -Message 'Starting retrieving ADFS Device Registration status.';

        try {
            $AdfsRegistration = Get-AdfsDeviceRegistration;
        }
        catch {
            Write-Verbose -Message ('Error occurred while retrieving ADFS properties: {0}' -f $global:Error[0].Exception.Message);
        }

        Write-Verbose -Message 'Finished retrieving ADFS Farm configuration.';
        return $this;
    }

    [System.Boolean] Test() {
        # Assume compliance by default
        $Compliant = $true;


        Write-Verbose -Message 'Testing for presence of Active Directory Federation Services (ADFS) farm.';

        try {
            $AdfsDeviceRegistration = Get-AdfsDeviceRegistration;
        }
        catch {
            $Compliant = $false;
            return $Compliant;
        }

        if ($this.Ensure -eq 'Present') {
            Write-Verbose -Message 'Checking for enabled ADFS Device Registration.';
        }

        if ($this.Ensure -eq 'Absent') {
            Write-Verbose -Message 'Checking for disabled ADFS Device Registration.';
            if ($AdfsDeviceRegistration) {
                Write-Verbose -Message
                $Compliant = $false;
            }
        }

        return $Compliant;
    }

    [void] Set() {

        ### If ADFS Farm shoud be present, then go ahead and install it.
        if ($this.Ensure -eq [Ensure]::Present) {
            Write-Verbose -Message 'Initializing Active Directory Device Registration.';

            $Initialize = @{
                ServiceAccountName = $this.ServiceAccountName
                DeviceLocation = $this.DomainName
                RegistrationQuota = $this.RegistrationQuota
                MaximumRegistrationInactivityPeriod = $this.MaximumRegistrationInactivityPeriod
                Credential = $this.InstallCredential
            };
            Initialize-ADDeviceRegistration @Initialize -Force

            Write-Verbose -Message 'Enabling ADFS Device Registration.';
            Enable-AdfsDeviceRegistration -Credential $this.InstallCredential -Force
        }

        if ($this.Ensure -eq [Ensure]::Absent) {
            Write-Verbose -Message 'Disabling ADFS Device Registration.';
            Disable-AdfsDeviceRegistration
        }

        return;
    }
}

<#
    .SYNOPSIS
    Locates one or more certificates using the passed certificate selector parameters.

    If more than one certificate is found matching the selector criteria, they will be
    returned in order of descending expiration date.

    .PARAMETER Thumbprint
    The thumbprint of the certificate to find.

    .PARAMETER FriendlyName
    The friendly name of the certificate to find.

    .PARAMETER Subject
    The subject of the certificate to find.

    .PARAMETER DNSName
    The subject alternative name of the certificate to export must contain these values.

    .PARAMETER Issuer
    The issuer of the certiicate to find.

    .PARAMETER KeyUsage
    The key usage of the certificate to find must contain these values.

    .PARAMETER EnhancedKeyUsage
    The enhanced key usage of the certificate to find must contain these values.

    .PARAMETER Store
    The Windows Certificate Store Name to search for the certificate in.
    Defaults to 'My'.

    .PARAMETER AllowExpired
    Allows expired certificates to be returned.

#>
function Find-Certificate {
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2[]])]
    param
    (
        [Parameter()]
        [String]
        $Thumbprint,

        [Parameter()]
        [String]
        $FriendlyName,

        [Parameter()]
        [String]
        $Subject,

        [Parameter()]
        [String[]]
        $DNSName,

        [Parameter()]
        [String]
        $Issuer,

        [Parameter()]
        [String[]]
        $KeyUsage,

        [Parameter()]
        [String[]]
        $EnhancedKeyUsage,

        [Parameter()]
        [String]
        $Store = 'My',

        [Parameter()]
        [Boolean]
        $AllowExpired = $false
    )

    $certPath = Join-Path -Path 'Cert:\LocalMachine' -ChildPath $Store

    if (-not (Test-Path -Path $certPath)) {
        # The Certificte Path is not valid
        New-InvalidArgumentError `
            -ErrorId 'CannotFindCertificatePath' `
            -ErrorMessage ($LocalizedData.CertificatePathError -f $certPath)
    } # if

    # Assemble the filter to use to select the certificate
    $certFilters = @()
    if ($PSBoundParameters.ContainsKey('Thumbprint')) {
        $certFilters += @('($_.Thumbprint -eq $Thumbprint)')
    } # if

    if ($PSBoundParameters.ContainsKey('FriendlyName')) {
        $certFilters += @('($_.FriendlyName -eq $FriendlyName)')
    } # if

    if ($PSBoundParameters.ContainsKey('Subject')) {
        $certFilters += @('($_.Subject -eq $Subject)')
    } # if

    if ($PSBoundParameters.ContainsKey('Issuer')) {
        $certFilters += @('($_.Issuer -eq $Issuer)')
    } # if

    if (-not $AllowExpired) {
        $certFilters += @('(((Get-Date) -le $_.NotAfter) -and ((Get-Date) -ge $_.NotBefore))')
    } # if

    if ($PSBoundParameters.ContainsKey('DNSName')) {
        $certFilters += @('(@(Compare-Object -ReferenceObject $_.DNSNameList.Unicode -DifferenceObject $DNSName | Where-Object -Property SideIndicator -eq "=>").Count -eq 0)')
    } # if

    if ($PSBoundParameters.ContainsKey('KeyUsage')) {
        $certFilters += @('(@(Compare-Object -ReferenceObject ($_.Extensions.KeyUsages -split ", ") -DifferenceObject $KeyUsage | Where-Object -Property SideIndicator -eq "=>").Count -eq 0)')
    } # if

    if ($PSBoundParameters.ContainsKey('EnhancedKeyUsage')) {
        $certFilters += @('(@(Compare-Object -ReferenceObject ($_.EnhancedKeyUsageList.FriendlyName) -DifferenceObject $EnhancedKeyUsage | Where-Object -Property SideIndicator -eq "=>").Count -eq 0)')
    } # if

    # Join all the filters together
    $certFilterScript = '(' + ($certFilters -join ' -and ') + ')'

    Write-Verbose -Message ($LocalizedData.SearchingForCertificateUsingFilters `
            -f $store, $certFilterScript)

    $certs = Get-ChildItem -Path $certPath |
        Where-Object -FilterScript ([ScriptBlock]::Create($certFilterScript))

    # Sort the certificates
    if ($certs.count -gt 1) {
        $certs = $certs | Sort-Object -Descending -Property 'NotAfter'
    } # if

    return $certs
} # end function Find-Certificate


<#
    .SYNOPSIS
    Convert a string containing an hashtable to an hashtable. This workaround is necessary because DSC in not handling properly hashtable properties.

    .PARAMETER String
    The string containing a JSON

#>
function Convert-StringToHashtable {
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $String
    )

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($String, [ref] $null, [ref] $null)
    $data = $ast.Find( { $args[0] -is [System.Management.Automation.Language.HashtableAst] }, $false )

    return [Hashtable] $data.SafeGetValue()
} # end function Convert-StringToHashtable

return;

<#
####### DOESN'T WORK DUE TO BUG #######
####### https://connect.microsoft.com/PowerShell/feedback/details/1191366

Write-Host -Object 'Loading cADFS module';

#region Import DSC Resources
$ResourceList = Get-ChildItem -Path $PSScriptRoot\Resources;

foreach ($Resource in $ResourceList) {
    Write-Verbose -Message ('Loading DSC resource from {0}' -f $Resource.FullName);
    . $Resource.FullName;
}
#endregion

Write-Host -Object 'Finished loading module.';
#>
