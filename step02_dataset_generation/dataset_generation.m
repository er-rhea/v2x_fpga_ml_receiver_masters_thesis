function dataset_generation(features, labels, frameIdx)
    filename = sprintf('step03_ml_model/dataset_x/frame_g%04d.mat', frameIdx);
    save(filename, 'features', 'labels');
end