fn main() -> Result<(), Box<dyn std::error::Error>> {
    std::fs::create_dir_all("src/generated")?;
    tonic_build::configure()
        .build_server(false)
        .out_dir("src/generated")
        .compile(
            &[
                "proto/yajudge_common.proto",
                "proto/yajudge_submissions.proto",
                "proto/yajudge_courses_content.proto",
            ],
            &["proto"],
        )?;
    Ok(())
}
