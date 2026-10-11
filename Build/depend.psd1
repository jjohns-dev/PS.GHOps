@{
    # Defaults for all dependencies
    PSDependOptions  = @{
        Target     = 'CurrentUser'
        Parameters = @{
            Repository         = 'PSGallery'
            SkipPublisherCheck = $true
        }
    }

    # Build/test tooling
    Pester           = '6.2.0'
    psake            = '5.0.4'
    PSScriptAnalyzer = '1.24.0'
}
